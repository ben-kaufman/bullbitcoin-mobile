import 'dart:typed_data';

import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/seed/data/datasources/seed_datasource.dart';
import 'package:bb_mobile/core/seed/data/models/seed_model.dart';
import 'package:bb_mobile/core/storage/tables/wallet_signer_table.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/datasources/frozen_wallet_utxo_datasource.dart';
import 'package:bb_mobile/core/wallet/data/datasources/wallet_metadata_datasource.dart';
import 'package:bb_mobile/core/wallet/data/mappers/bitcoin_psbt_review_mapper.dart';
import 'package:bb_mobile/core/wallet/data/mappers/bitcoin_policy_maturity_mapper.dart';
import 'package:bb_mobile/core/wallet/data/mappers/bitcoin_wallet_policy_mapper.dart';
import 'package:bb_mobile/core/wallet/data/mappers/wallet_utxo_mapper.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_metadata_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_model.dart';
import 'package:bb_mobile/core/electrum/domain/value_objects/electrum_connection.dart';
import 'package:bb_mobile/core/electrum/domain/ports/electrum_servers_port.dart';
import 'package:bb_mobile/core/electrum/domain/value_objects/electrum_server_network.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_psbt_review.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_utxo.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_send_port.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_psbt_review_exception.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bull_sdk/bdk.dart' as bdk;

class BitcoinWalletRepository implements BitcoinSendPort, BitcoinSigningPort {
  final WalletMetadataDatasource _walletMetadataDatasource;
  final SeedDatasource _seed;
  final BdkWalletDatasource _bdkWallet;
  final FrozenWalletUtxoDatasource _frozenUtxos;
  final ElectrumServersPort? electrumServers;

  BitcoinWalletRepository({
    required this._walletMetadataDatasource,
    required SeedDatasource seedDatasource,
    required BdkWalletDatasource bdkWalletDatasource,
    required FrozenWalletUtxoDatasource frozenWalletUtxoDatasource,
    this.electrumServers,
  }) : _seed = seedDatasource,
       _bdkWallet = bdkWalletDatasource,
       _frozenUtxos = frozenWalletUtxoDatasource;

  @override
  Future<String> buildPsbt({
    required String walletId,
    required String address,
    int? amountSat,
    required NetworkFee networkFee,
    bool? drain,
    List<({String txId, int vout})>? unspendable,
    List<WalletUtxo>? selected,
    bool? replaceByFee,
    BitcoinPolicyPath? policyPath,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);

    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }

    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final wallet =
        WalletModel.publicBdk(
              descriptor: metadata.publicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;

    // A frozen coin must never be spendable. Read the frozen store at build
    // time so the invariant holds for every caller and does not depend on an
    // earlier UTXO snapshot. Payjoin exclusions remain supplied by the use
    // case because they come from a separate repository.
    //
    // The frozen set read here is:
    //  * merged into `unspendable`, so BDK's automatic selection can
    //    never pick a frozen coin even when the caller passed no
    //    exclusion list at all;
    //  * checked against `selected` by the datasource, so a frozen coin
    //    causes manual selection to fail instead of being substituted.
    final frozenRows = await _frozenUtxos.getAllFrozen();
    final mergedUnspendable = [
      for (final outpoint in {
        for (final row in frozenRows) (txId: row.txId, vout: row.vout),
        ...?unspendable,
      })
        outpoint,
    ];
    final psbt = await _bdkWallet.buildPsbt(
      wallet: wallet,
      address: address,
      amountSat: amountSat,
      networkFee: networkFee,
      drain: drain,
      // An empty merged list is equivalent to null for the datasource
      // (it gates on isNotEmpty), so always pass the merge.
      unspendable: mergedUnspendable,
      selected: selected
          ?.map((utxo) => WalletUtxoMapper.fromEntity(utxo))
          .toList(),
      // Default to RBF-enabled, matching both the datasource default and
      // BDK's own default sequence (0xFFFFFFFD). `?? false` would disable
      // RBF for any caller omitting the flag — harmless while
      // setExactSequence's result was discarded, wrong now that it works.
      replaceByFee: replaceByFee ?? true,
      policyPath: policyPath,
    );

    return psbt;
  }

  @override
  Future<({String psbt, bool isFinalized})> signPsbt(
    String psbt, {
    required String walletId,
    bool tryFinalize = true,
    String? signerId,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);
    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }
    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    var descriptor = _withoutDescriptorChecksum(metadata.publicDescriptor);
    var injectedKey = false;
    final localSigners = metadata.signers.where(
      (signer) =>
          signer.signer == Signer.local &&
          (signerId == null || signer.id == signerId),
    );
    for (final signer in localSigners) {
      for (final key in signer.descriptorKeys) {
        final derivationPath = key.derivationPath;
        if (derivationPath == null) {
          throw StateError('Local descriptor key has no derivation path');
        }
        final seed = await _seed.get(key.masterFingerprint);
        final rootKey = _descriptorSecretKey(seed, network: metadata.network);
        try {
          final path = bdk.DerivationPath(path: derivationPath);
          try {
            final accountKey = rootKey.derive(path: path);
            try {
              final publicKey = accountKey.asPublic();
              try {
                final publicKeyString = publicKey.toString();
                final privateKeyString = accountKey.toString();
                final descriptorWithKey = descriptor.replaceAll(
                  publicKeyString,
                  privateKeyString,
                );
                if (descriptorWithKey == descriptor) {
                  throw StateError(
                    'Local descriptor key is not present in descriptors',
                  );
                }
                descriptor = descriptorWithKey;
                injectedKey = true;
              } finally {
                publicKey.dispose();
              }
            } finally {
              accountKey.dispose();
            }
          } finally {
            path.dispose();
          }
        } finally {
          rootKey.dispose();
        }
      }
    }
    if (!injectedKey) throw StateError('Wallet has no local signer');

    return _bdkWallet.signPsbtWithDescriptor(
      psbt,
      descriptor: descriptor,
      isTestnet: metadata.isTestnet,
      tryFinalize: tryFinalize,
    );
  }

  @override
  Future<BitcoinPsbtReview> reviewPsbt(
    String psbt, {
    required String walletId,
    bool requireLocalOrigin = true,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);
    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }
    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final wallet =
        WalletModel.publicBdk(
              descriptor: metadata.publicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;
    final localSignerIds = metadata.signers
        .where((signer) => signer.signer == Signer.local)
        .map((signer) => signer.id)
        .toSet();
    if (requireLocalOrigin && localSignerIds.isEmpty) {
      throw StateError('Wallet has no local signer');
    }

    try {
      final model = _bdkWallet.inspectPsbt(
        psbt,
        wallet: wallet,
        walletFingerprints: metadata.signers
            .expand((signer) => signer.descriptorKeys)
            .expand((key) => [key.masterFingerprint, key.xpubFingerprint])
            .where((fingerprint) => fingerprint.isNotEmpty)
            .map((fingerprint) => fingerprint.toLowerCase())
            .toSet(),
      );
      final review = BitcoinPsbtReviewMapper.toEntity(
        model,
        descriptorKeys: metadata.signers
            .expand((signer) => signer.descriptorKeys)
            .toList(),
        localSignerIds: localSignerIds,
      );
      final walletUtxos = await _bdkWallet.getUtxos(wallet: wallet);
      final amountByOutpoint = {
        for (final utxo in walletUtxos) utxo.labelRef: utxo.amountSat,
      };
      if (review.inputs.any(
        (input) => amountByOutpoint[input.outpoint] != input.amountSat,
      )) {
        throw const BitcoinPsbtMissingUtxoException();
      }
      if (requireLocalOrigin &&
          !review.inputs.any((input) => input.hasLocalSignerOrigin)) {
        throw const BitcoinPsbtMissingLocalOriginException();
      }
      return review;
    } on BitcoinPsbtReviewException {
      rethrow;
    } on Exception {
      throw const InvalidBitcoinPsbtException();
    }
  }

  @override
  Future<BitcoinWalletPolicy> getPolicy({required String walletId}) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);
    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }
    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    return BitcoinWalletPolicyMapper.toEntity(
      _bdkWallet.analyzePolicy(
        wallet:
            WalletModel.publicBdk(
                  descriptor: metadata.publicDescriptor,
                  isTestnet: metadata.isTestnet,
                  id: metadata.id,
                )
                as PublicBdkWalletModel,
        descriptorKeys: metadata.signers
            .expand((signer) => signer.descriptorKeys)
            .toList(),
      ),
    );
  }

  @override
  Future<BitcoinPolicyMaturity> getPolicyMaturity({
    required String walletId,
    required bool includeTimeBasedLocks,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);
    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }
    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final wallet =
        WalletModel.publicBdk(
              descriptor: metadata.publicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;
    final cachedModel = await _bdkWallet.getPolicyMaturity(
      wallet: wallet,
      includeTimeBasedLocks: includeTimeBasedLocks,
    );
    final servers = electrumServers;
    if (servers == null) {
      return BitcoinPolicyMaturityMapper.toEntity(cachedModel);
    }

    try {
      final model = await servers.runWithFallback(
        network: ElectrumServerNetwork.fromEnvironment(
          isTestnet: metadata.isTestnet,
          isLiquid: false,
        ),
        operation: (connection) => _bdkWallet.getPolicyMaturity(
          wallet: wallet,
          electrumServer: connection,
          includeTimeBasedLocks: includeTimeBasedLocks,
        ),
      );
      return BitcoinPolicyMaturityMapper.toEntity(model);
    } on Exception {
      // Cached height remains safe: stale data only keeps a path hidden longer.
      // Time-based paths stay unavailable until median-time-past is known.
      return BitcoinPolicyMaturityMapper.toEntity(cachedModel);
    }
  }

  @override
  Future<({String psbt, bool isFinalized})> combinePsbts({
    required String currentPsbt,
    required String signedPsbt,
    required String walletId,
    bool tryFinalize = true,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);
    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }
    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }
    final wallet =
        WalletModel.publicBdk(
              descriptor: metadata.publicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;
    _bdkWallet.validateExternalPartialPsbt(
      currentPsbtBase64: currentPsbt,
      signedPsbtBase64: signedPsbt,
    );
    final combined = _bdkWallet.combinePsbts(
      first: currentPsbt,
      second: signedPsbt,
    );
    _bdkWallet.inspectPsbt(
      combined,
      wallet: wallet,
      walletFingerprints: metadata.signers
          .expand((signer) => signer.descriptorKeys)
          .expand((key) => [key.masterFingerprint, key.xpubFingerprint])
          .where((fingerprint) => fingerprint.isNotEmpty)
          .map((fingerprint) => fingerprint.toLowerCase())
          .toSet(),
    );
    return tryFinalize
        ? _bdkWallet.finalizePsbt(combined)
        : (psbt: combined, isFinalized: false);
  }

  @override
  Future<({String psbt, bool isFinalized})> finalizePsbt(String psbt) async =>
      _bdkWallet.finalizePsbt(psbt);

  @override
  Future<bool> validatePolicyPreimage(BitcoinPolicyPreimage preimage) async =>
      _bdkWallet.validatePolicyPreimage(preimage);

  @override
  Future<String> applyPolicyPreimages({
    required String psbt,
    required List<BitcoinPolicyPreimage> preimages,
  }) async => _bdkWallet.applyPolicyPreimages(psbt, preimages);

  @override
  Future<({String transaction, int txSize})> verifyFinalTransaction({
    required String psbt,
    required String transaction,
  }) async => _bdkWallet.verifyFinalTransaction(
    psbtBase64: psbt,
    transactionHex: transaction,
  );

  Future<bool> isScriptOfWallet({
    required String walletId,
    required Uint8List script,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);

    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }

    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final wallet =
        WalletModel.publicBdk(
              descriptor: metadata.publicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;

    final isFromWallet = await _bdkWallet.isMine(script, wallet: wallet);

    return isFromWallet;
  }

  @override
  Future<bool> isAddressOfWallet(
    String address, {
    required String walletId,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);

    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }

    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final wallet =
        WalletModel.publicBdk(
              descriptor: metadata.publicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;

    final isFromWallet = await _bdkWallet.isAddressMine(
      address,
      wallet: wallet,
    );

    return isFromWallet;
  }

  @override
  Future<int> getTxSize({
    required String psbt,
    required String walletId,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);
    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }
    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }
    final wallet =
        WalletModel.publicBdk(
              descriptor: metadata.publicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;
    return _bdkWallet.decodeTxSize(psbt, wallet: wallet);
  }

  Future<int> getTxFeeAmount({required String psbt}) async {
    final feeAbsolute = await _bdkWallet.getFeeAmount(psbt);
    return feeAbsolute;
  }

  Future<int> getAmountSentToAddress({
    required String psbt,
    required String address,
    required String walletId,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);
    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }
    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }
    return await _bdkWallet.getAmountSentToAddress(
      psbt,
      address,
      isTestnet: metadata.isTestnet,
    );
  }

  Future<PrivateBdkWalletModel> getPrivateWallet({
    required String walletId,
  }) async {
    final metadata = await _walletMetadataDatasource.fetch(walletId);

    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }

    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final scriptType = metadata.scriptType;
    if (metadata.signers.length != 1 || scriptType == null) {
      throw StateError('Standard local single-signature wallet required');
    }
    final signer = metadata.soleSigner;
    final key = metadata.soleDescriptorKey;
    if (signer.signer != Signer.local ||
        !scriptType.matchesStandardAccountPath(
          key.derivationPath,
          metadata.network,
        ) ||
        !descriptorUsesStandardKeychains(metadata.publicDescriptor)) {
      throw StateError('Standard local single-signature wallet required');
    }

    final seed = await _seed.get(key.masterFingerprint);
    if (seed is! MnemonicSeedModel) {
      throw StateError('Standard local single-signature wallet required');
    }
    final mnemonic = seed.mnemonicWords.join(' ');

    final wallet =
        WalletModel.privateBdk(
              id: metadata.id,
              mnemonic: mnemonic,
              passphrase: seed.passphrase,
              scriptType: scriptType,
              isTestnet: metadata.isTestnet,
            )
            as PrivateBdkWalletModel;
    return wallet;
  }

  Future<({BigInt satoshis, int transactions})> dryScan({
    required List<int> entropy,
    required String passphrase,
    required ScriptType scriptType,
    required bool isTestnet,
    required ElectrumConnection electrumServer,
  }) {
    return _bdkWallet.dryScan(
      entropy: entropy,
      passphrase: passphrase,
      scriptType: scriptType,
      isTestnet: isTestnet,
      electrumServer: electrumServer,
    );
  }

  Future<String> bumpFee({
    required String walletId,
    required String txid,
    required RelativeFee newFeeRate,
  }) async {
    final wallet = await getPrivateWallet(walletId: walletId);
    final psbt = await _bdkWallet.createUnsignedReplaceByFeePsbt(
      wallet: wallet,
      txid: txid,
      feeRate: newFeeRate,
    );
    final signed = await signPsbt(psbt, walletId: walletId);
    if (!signed.isFinalized) {
      throw StateError('Replacement transaction is not fully signed');
    }
    return signed.psbt;
  }

  bdk.DescriptorSecretKey _descriptorSecretKey(
    SeedModel seed, {
    required Network network,
  }) {
    if (seed is MnemonicSeedModel) {
      final mnemonic = bdk.Mnemonic.fromString(
        mnemonic: seed.mnemonicWords.join(' '),
      );
      try {
        return bdk.DescriptorSecretKey(
          networkKind: network.isTestnet
              ? bdk.NetworkKind.test
              : bdk.NetworkKind.main,
          mnemonic: mnemonic,
          password: seed.passphrase,
        );
      } finally {
        mnemonic.dispose();
      }
    }

    final xprv = Bip32Derivation.getXprvFromSeed(
      Uint8List.fromList(seed.bytes),
      network,
    );
    return bdk.DescriptorSecretKey.fromString(privateKey: xprv);
  }

  String _withoutDescriptorChecksum(String descriptor) =>
      descriptor.split('#').first;
}
