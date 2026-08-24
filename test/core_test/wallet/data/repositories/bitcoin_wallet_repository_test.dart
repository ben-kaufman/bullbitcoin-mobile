import 'dart:typed_data';

import 'package:bb_mobile/core/seed/data/datasources/seed_datasource.dart';
import 'package:bb_mobile/core/seed/data/models/seed_model.dart';
import 'package:bb_mobile/core/storage/tables/wallet_signer_table.dart';
import 'package:bb_mobile/core/utils/descriptor_derivation.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/datasources/frozen_wallet_utxo_datasource.dart';
import 'package:bb_mobile/core/wallet/data/datasources/wallet_metadata_datasource.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_metadata_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_model.dart';
import 'package:bb_mobile/core/wallet/data/models/bitcoin_psbt_review_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_utxo_model.dart';
import 'package:bb_mobile/core/wallet/data/repositories/bitcoin_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_psbt_review_exception.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bull_sdk/bdk.dart' as bdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../bdk_wallet_test_fixture.dart';
import '../../wallet_signer_test_fixture.dart';

class _MockWalletMetadataDatasource extends Mock
    implements WalletMetadataDatasource {}

class _MockSeedDatasource extends Mock implements SeedDatasource {}

class _MockFrozenWalletUtxoDatasource extends Mock
    implements FrozenWalletUtxoDatasource {}

class _MockBdkWalletDatasource extends Mock implements BdkWalletDatasource {}

typedef _SignerFixture = ({
  String externalPublic,
  String fingerprint,
  String internalPublic,
  SeedModel seed,
  String xpub,
});

void main() {
  late WalletMetadataDatasource metadataDatasource;
  late SeedDatasource seedDatasource;
  late BdkWalletDatasource bdkDatasource;
  late FrozenWalletUtxoDatasource frozenWalletUtxoDatasource;
  late BitcoinWalletRepository repository;

  setUp(() {
    metadataDatasource = _MockWalletMetadataDatasource();
    seedDatasource = _MockSeedDatasource();
    bdkDatasource = BdkWalletDatasource();
    frozenWalletUtxoDatasource = _MockFrozenWalletUtxoDatasource();
    repository = BitcoinWalletRepository(
      walletMetadataDatasource: metadataDatasource,
      seedDatasource: seedDatasource,
      bdkWalletDatasource: bdkDatasource,
      frozenWalletUtxoDatasource: frozenWalletUtxoDatasource,
    );
  });

  void stubWallet(
    WalletMetadataModel metadata,
    List<_SignerFixture> localSigners,
  ) {
    when(
      () => metadataDatasource.fetch(metadata.id),
    ).thenAnswer((_) async => metadata);
    for (final signer in localSigners) {
      when(
        () => seedDatasource.get(signer.fingerprint),
      ).thenAnswer((_) async => signer.seed);
    }
  }

  test('single local signer finalizes a mobile wallet PSBT', () async {
    final signer = _singleSignatureFixture(testMnemonics.first);
    final metadata = _metadata(
      descriptor: twoPathDescriptor(
        signer.externalPublic,
        signer.internalPublic,
      ),
      signers: [signer],
      localSignerCount: 1,
    );
    stubWallet(metadata, [signer]);
    final unsignedPsbt = buildUnsignedPsbt(
      descriptor: twoPathDescriptor(
        signer.externalPublic,
        signer.internalPublic,
      ),
    );

    final signed = await repository.signPsbt(
      unsignedPsbt,
      walletId: metadata.id,
    );

    expect(signed.isFinalized, isTrue);
  });

  test('private wallet reconstruction rejects nonstandard keychains', () async {
    final signer = _singleSignatureFixture(testMnemonics.first);
    final metadata = _metadata(
      descriptor: signer.externalPublic.replaceAll('/0/*', '/2/*'),
      signers: [signer],
      localSignerCount: 1,
    );
    stubWallet(metadata, const []);

    expect(
      () => repository.getPrivateWallet(walletId: metadata.id),
      throwsStateError,
    );
  });

  test('preserves an existing PSBT when adding a local signature', () async {
    final signer = _singleSignatureFixture(testMnemonics.first);
    final metadata = _metadata(
      descriptor: twoPathDescriptor(
        signer.externalPublic,
        signer.internalPublic,
      ),
      signers: [signer],
      localSignerCount: 1,
    );
    stubWallet(metadata, [signer]);
    final unsignedPsbt = buildUnsignedPsbt(
      descriptor: twoPathDescriptor(
        signer.externalPublic,
        signer.internalPublic,
      ),
    );

    final signed = await repository.signPsbt(
      unsignedPsbt,
      walletId: metadata.id,
      tryFinalize: false,
    );

    expect(signed.isFinalized, isFalse);
    expect(signedFingerprints(signed.psbt), {signer.fingerprint.toLowerCase()});
  });

  test('adds a partial signature for a delayed Miniscript path', () async {
    final remote = _multisigFixture(testMnemonics.first);
    final local = _miniscriptBip84Fixture(testMnemonics[1]);
    final externalDescriptor = bdk.Descriptor.newWsh(
      miniScript:
          'or_d(pk(${remote.externalPublic}),and_v(v:pkh(${local.externalPublic}),older(1)))',
    ).toString();
    final internalDescriptor = bdk.Descriptor.newWsh(
      miniScript:
          'or_d(pk(${remote.internalPublic}),and_v(v:pkh(${local.internalPublic}),older(1)))',
    ).toString();
    final metadata = WalletMetadataModel(
      id: 'wallet',
      network: Network.bitcoinTestnet,
      signers: [
        walletSignerModel(
          id: 'signer-0',
          descriptorKeyId: 'key-0',
          masterFingerprint: remote.fingerprint,
          xpubFingerprint: remote.fingerprint,
          xpub: remote.xpub,
          derivationPath: "m/48'/1'/0'/2'",
          signer: Signer.remote,
          signerDevice: null,
        ),
        walletSignerModel(
          id: 'signer-1',
          descriptorKeyId: 'key-1',
          masterFingerprint: local.fingerprint,
          xpubFingerprint: local.fingerprint,
          xpub: local.xpub,
          derivationPath: "m/84'/1'/0'",
          signer: Signer.local,
          signerDevice: null,
        ),
      ],
      isEncryptedVaultTested: false,
      isPhysicalBackupTested: false,
      publicDescriptor: twoPathDescriptor(
        externalDescriptor,
        internalDescriptor,
      ),
      isDefault: false,
    );
    stubWallet(metadata, [local]);
    final publicWallet =
        WalletModel.publicBdk(
              id: metadata.id,
              descriptor: twoPathDescriptor(
                externalDescriptor,
                internalDescriptor,
              ),
              isTestnet: true,
            )
            as PublicBdkWalletModel;
    final policy = await repository.getPolicy(walletId: metadata.id);
    final selector = policy
        .pathSelectors(const BitcoinPolicySelection.empty())
        .single;
    final delayedIndex = selector.options.indexWhere(
      containsPolicyNode<BitcoinRelativeTimelockPolicyNode>,
    );
    final selection = policy.select(
      current: const BitcoinPolicySelection.empty(),
      requirement: selector,
      selectedIndices: {delayedIndex},
    );
    final unsignedPsbt = buildUnsignedPsbt(
      descriptor: twoPathDescriptor(externalDescriptor, internalDescriptor),
      policyPath: policy.buildPath(selection),
    );

    final signed = await repository.signPsbt(
      unsignedPsbt,
      walletId: metadata.id,
      tryFinalize: false,
    );

    expect(signed.isFinalized, isFalse);
    expect(signedFingerprints(signed.psbt), {local.fingerprint.toLowerCase()});
    expect(
      () => bdkDatasource.inspectPsbt(
        signed.psbt,
        wallet: publicWallet,
        walletFingerprints: {remote.fingerprint, local.fingerprint},
      ),
      returnsNormally,
    );
  });

  test('one local multisig key returns a partial PSBT', () async {
    final signers = testMnemonics.map(_multisigFixture).toList();
    final metadata = _multisigMetadata(signers, localSignerCount: 1);
    stubWallet(metadata, signers.take(1).toList());
    final unsignedPsbt = buildUnsignedPsbt(
      descriptor: metadata.publicDescriptor,
    );

    final signed = await repository.signPsbt(
      unsignedPsbt,
      walletId: metadata.id,
    );

    expect(signed.isFinalized, isFalse);
    expect(bdkDatasource.finalizePsbt(signed.psbt).isFinalized, isFalse);
  });

  test('enough local multisig keys finalize the PSBT', () async {
    final signers = testMnemonics.map(_multisigFixture).toList();
    final metadata = _multisigMetadata(signers, localSignerCount: 2);
    stubWallet(metadata, signers.take(2).toList());
    final unsignedPsbt = buildUnsignedPsbt(
      descriptor: metadata.publicDescriptor,
    );

    final signed = await repository.signPsbt(
      unsignedPsbt,
      walletId: metadata.id,
    );

    expect(signed.isFinalized, isTrue);
  });

  test('signs with only the selected local multisig key', () async {
    final signers = testMnemonics.map(_multisigFixture).toList();
    final metadata = _multisigMetadata(signers, localSignerCount: 2);
    stubWallet(metadata, signers.take(2).toList());
    final unsignedPsbt = buildUnsignedPsbt(
      descriptor: metadata.publicDescriptor,
    );

    final signed = await repository.signPsbt(
      unsignedPsbt,
      walletId: metadata.id,
      tryFinalize: false,
      signerId: 'signer-1',
    );

    expect(signedFingerprints(signed.psbt), {
      signers[1].fingerprint.toLowerCase(),
    });
  });

  test('rejects a PSBT whose witness UTXO amount differs from the wallet', () {
    final signer = _singleSignatureFixture(testMnemonics.first);
    final descriptor = twoPathDescriptor(
      signer.externalPublic,
      signer.internalPublic,
    );
    final metadata = _metadata(
      descriptor: descriptor,
      signers: [signer],
      localSignerCount: 1,
    );
    final wallet =
        WalletModel.publicBdk(
              id: metadata.id,
              descriptor: descriptor,
              isTestnet: true,
            )
            as PublicBdkWalletModel;
    final datasource = _MockBdkWalletDatasource();
    final reviewModel = BitcoinPsbtReviewModel(
      transactionId: 'transaction',
      inputs: [
        (
          amountSat: BigInt.from(2000),
          keychain: BitcoinPolicyKeychain.external,
          originKeySources: const [],
          signedKeySources: const [],
          tapLeafHashes: const {},
          outpoint: 'funding:0',
          sequence: 0xffffffff,
        ),
      ],
      outputs: [
        (
          address: 'address',
          amountSat: BigInt.from(1000),
          index: 0,
          isWalletOwned: false,
          scriptHex: '00',
        ),
      ],
      feeSat: BigInt.from(1000),
      estimatedTransactionVsize: 100,
      lockTime: 0,
      version: 2,
    );
    when(
      () => metadataDatasource.fetch(metadata.id),
    ).thenAnswer((_) async => metadata);
    when(
      () => datasource.inspectPsbt(
        'psbt',
        wallet: wallet,
        walletFingerprints: {signer.fingerprint.toLowerCase()},
      ),
    ).thenReturn(reviewModel);
    when(() => datasource.getUtxos(wallet: wallet)).thenAnswer(
      (_) async => [
        WalletUtxoModel.bitcoin(
          txId: 'funding',
          vout: 0,
          amountSat: BigInt.from(1000),
          scriptPubkey: Uint8List(0),
          address: 'address',
          isExternalKeyChain: true,
        ),
      ],
    );
    final reviewRepository = BitcoinWalletRepository(
      walletMetadataDatasource: metadataDatasource,
      seedDatasource: seedDatasource,
      bdkWalletDatasource: datasource,
      frozenWalletUtxoDatasource: frozenWalletUtxoDatasource,
    );

    expect(
      () => reviewRepository.reviewPsbt(
        'psbt',
        walletId: metadata.id,
        requireLocalOrigin: false,
      ),
      throwsA(isA<BitcoinPsbtMissingUtxoException>()),
    );
  });
}

WalletMetadataModel _multisigMetadata(
  List<_SignerFixture> signers, {
  required int localSignerCount,
}) {
  final externalDescriptor =
      DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
        threshold: 2,
        descriptorKeys: signers.map((signer) => signer.externalPublic).toList(),
      );
  final internalDescriptor =
      DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
        threshold: 2,
        descriptorKeys: signers.map((signer) => signer.internalPublic).toList(),
      );
  return _metadata(
    descriptor: twoPathDescriptor(externalDescriptor, internalDescriptor),
    signers: signers,
    localSignerCount: localSignerCount,
  );
}

WalletMetadataModel _metadata({
  required String descriptor,
  required List<_SignerFixture> signers,
  required int localSignerCount,
}) => WalletMetadataModel(
  id: 'wallet',
  network: Network.bitcoinTestnet,
  signers: [
    for (final (index, signer) in signers.indexed)
      walletSignerModel(
        id: 'signer-$index',
        descriptorKeyId: 'key-$index',
        masterFingerprint: signer.fingerprint,
        xpubFingerprint: signer.fingerprint,
        xpub: signer.xpub,
        derivationPath: signers.length == 1 ? "m/84'/1'/0'" : "m/48'/1'/0'/2'",
        signer: index < localSignerCount ? Signer.local : Signer.remote,
        signerDevice: null,
      ),
  ],
  isEncryptedVaultTested: false,
  isPhysicalBackupTested: false,
  publicDescriptor: descriptor,
  isDefault: false,
);

_SignerFixture _singleSignatureFixture(String words) {
  final seed = SeedModel.mnemonic(mnemonicWords: words.split(' '));
  final descriptors = singleSignatureDescriptors(words);
  return (
    externalPublic: descriptors.external,
    fingerprint: descriptors.fingerprint,
    internalPublic: descriptors.internal,
    seed: seed,
    xpub: descriptors.xpub,
  );
}

_SignerFixture _multisigFixture(String words) {
  final seed = SeedModel.mnemonic(mnemonicWords: words.split(' '));
  final keys = deriveSignerKeys(words);
  return (
    externalPublic: keys.externalPublic,
    fingerprint: keys.fingerprint,
    internalPublic: keys.internalPublic,
    seed: seed,
    xpub: keys.xpub,
  );
}

_SignerFixture _miniscriptBip84Fixture(String words) {
  final seed = SeedModel.mnemonic(mnemonicWords: words.split(' '));
  final root = bdk.DescriptorSecretKey(
    networkKind: bdk.NetworkKind.test,
    mnemonic: bdk.Mnemonic.fromString(mnemonic: words),
    password: null,
  );
  final account = root.derive(path: bdk.DerivationPath(path: "m/84'/1'/0'"));
  final public = account.asPublic();
  return (
    externalPublic: '$public/0/*',
    fingerprint: public.masterFingerprint(),
    internalPublic: '$public/1/*',
    seed: seed,
    xpub: public.toString(),
  );
}
