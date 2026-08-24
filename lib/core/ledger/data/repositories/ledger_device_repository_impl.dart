import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/ledger/data/datasources/ledger_device_datasource.dart';
import 'package:bb_mobile/core/ledger/data/datasources/ledger_wallet_policy_hmac_datasource.dart';
import 'package:bb_mobile/core/ledger/data/ledger_wallet_policy_adapter.dart';
import 'package:bb_mobile/core/ledger/data/models/ledger_device_model.dart';
import 'package:bb_mobile/core/ledger/domain/entities/ledger_device_entity.dart';
import 'package:bb_mobile/core/ledger/domain/errors/ledger_errors.dart';
import 'package:bb_mobile/core/ledger/domain/repositories/ledger_device_repository.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_descriptor_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_descriptor_key.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:ledger_bitcoin/ledger_bitcoin.dart';

class LedgerDeviceRepositoryImpl implements LedgerDeviceRepository {
  final LedgerDeviceDatasource _datasource;
  final LedgerWalletPolicyHmacDatasource _hmacDatasource;
  final BitcoinDescriptorPort _descriptorPort;

  LedgerDeviceRepositoryImpl({
    required this._datasource,
    required this._hmacDatasource,
    required BitcoinDescriptorPort bitcoinDescriptorPort,
  }) : _descriptorPort = bitcoinDescriptorPort;

  @override
  Future<List<LedgerDeviceEntity>> scanDevices({
    SignerDeviceEntity? deviceType,
  }) async {
    final models = await _datasource.scanDevices(deviceType: deviceType);
    return models.map((model) => model.toEntity()).toList();
  }

  @override
  Future<void> connectDevice(LedgerDeviceEntity device) async {
    final model = device.toModel();
    await _datasource.connectDevice(model);
  }

  @override
  Future<String> getXpub(
    LedgerDeviceEntity device, {
    required String derivationPath,
    required ScriptType scriptType,
  }) async {
    final model = device.toModel();
    return await _datasource.getXpub(
      model,
      derivationPath: derivationPath,
      scriptType: scriptType,
    );
  }

  @override
  Future<String> getMasterFingerprint(LedgerDeviceEntity device) async {
    final model = device.toModel();
    return await _datasource.getMasterFingerprint(model);
  }

  @override
  Future<String> signPsbt(
    LedgerDeviceEntity device, {
    required String psbt,
    required String derivationPath,
    required ScriptType scriptType,
  }) async {
    final model = device.toModel();
    return await _datasource.signPsbt(
      model,
      psbt: psbt,
      derivationPath: derivationPath,
      scriptType: scriptType,
    );
  }

  @override
  Future<bool> verifyAddress(
    LedgerDeviceEntity device, {
    required String address,
    required String derivationPath,
    required ScriptType scriptType,
  }) async {
    final model = device.toModel();
    return await _datasource.verifyAddress(
      model,
      address: address,
      derivationPath: derivationPath,
      scriptType: scriptType,
    );
  }

  @override
  Future<void> registerWalletPolicy(
    LedgerDeviceEntity device, {
    required Wallet wallet,
  }) async {
    _ensureSupportedPolicy(wallet);
    final model = device.toModel();
    final descriptor = _analyzePolicyDescriptor(wallet);
    final walletPolicy = _walletPolicy(wallet, descriptor.policyKeys);
    final policyId = hex.encode(walletPolicy.id);
    await _ensureSupportedFirmware(
      model,
      wallet: wallet,
      hasUnspendablePolicyKey: descriptor.hasUnspendablePolicyKey,
    );
    final signer = await _matchWalletSigner(model, wallet: wallet);
    final hmac = await _executeWalletPolicyOperation(
      () => _datasource.registerWalletPolicy(model, walletPolicy: walletPolicy),
    );
    await _hmacDatasource.save(
      walletId: wallet.id,
      signerId: signer.id,
      policyId: policyId,
      hmac: hmac,
    );
  }

  @override
  Future<String> signWalletPsbt(
    LedgerDeviceEntity device, {
    required Wallet wallet,
    required String signerId,
    required String psbt,
  }) async {
    _ensureSupportedPolicy(wallet);
    final model = device.toModel();
    final descriptor = _analyzePolicyDescriptor(wallet);
    final walletPolicy = _walletPolicy(wallet, descriptor.policyKeys);
    final policyId = hex.encode(walletPolicy.id);
    await _ensureSupportedFirmware(
      model,
      wallet: wallet,
      hasUnspendablePolicyKey: descriptor.hasUnspendablePolicyKey,
    );
    final signer = await _matchWalletSigner(
      model,
      wallet: wallet,
      signerId: signerId,
    );
    final hmac = await _registeredHmac(wallet.id, signer.id, policyId);
    return _executeWalletPolicyOperation(
      () => _datasource.signWalletPsbt(
        model,
        walletPolicy: walletPolicy,
        walletHmac: hmac,
        psbt: psbt,
      ),
    );
  }

  @override
  Future<bool> verifyWalletAddress(
    LedgerDeviceEntity device, {
    required Wallet wallet,
    required String address,
    required BitcoinPolicyKeychain keychain,
    required int index,
  }) async {
    _ensureSupportedPolicy(wallet);
    final model = device.toModel();
    final descriptor = _analyzePolicyDescriptor(wallet);
    final walletPolicy = _walletPolicy(wallet, descriptor.policyKeys);
    final policyId = hex.encode(walletPolicy.id);
    await _ensureSupportedFirmware(
      model,
      wallet: wallet,
      hasUnspendablePolicyKey: descriptor.hasUnspendablePolicyKey,
    );
    final signer = await _matchWalletSigner(model, wallet: wallet);
    final hmac = await _registeredHmac(wallet.id, signer.id, policyId);
    final verifiedAddress = await _executeWalletPolicyOperation(
      () => _datasource.verifyWalletAddress(
        model,
        walletPolicy: walletPolicy,
        walletHmac: hmac,
        keychain: keychain,
        index: index,
      ),
    );
    if (verifiedAddress != address) {
      throw LedgerError.operationFailed(
        message: 'LEDGER_ERROR_ADDRESS_MISMATCH',
      );
    }
    return true;
  }

  Future<WalletSigner> _matchWalletSigner(
    LedgerDeviceModel device, {
    required Wallet wallet,
    String? signerId,
  }) async {
    final fingerprint = (await _datasource.getMasterFingerprint(
      device,
    )).toLowerCase();
    final candidates = wallet.signers.where(
      (signer) =>
          signer.signerDevice?.isLedger == true &&
          (signerId == null || signer.id == signerId),
    );
    for (final signer in candidates) {
      if (signer.descriptorKeys.any(
        (key) => key.masterFingerprint.toLowerCase() != fingerprint,
      )) {
        continue;
      }
      var matches = true;
      for (final key in signer.descriptorKeys) {
        final path = key.derivationPath;
        if (path == null || key.xpub.isEmpty) {
          matches = false;
          break;
        }
        final xpub = await _datasource.getWalletPolicyXpub(
          device,
          derivationPath: path,
        );
        if (!_sameXpub(xpub, key.xpub)) {
          matches = false;
          break;
        }
      }
      if (matches) return signer;
    }
    throw LedgerError.operationFailed(
      message: 'LEDGER_ERROR_WALLET_SIGNER_MISMATCH',
    );
  }

  Future<void> _ensureSupportedFirmware(
    LedgerDeviceModel device, {
    required Wallet wallet,
    required bool hasUnspendablePolicyKey,
  }) async {
    final minimumVersion = LedgerWalletPolicyAdapter.minimumBitcoinAppVersion(
      wallet,
      hasUnspendablePolicyKey: hasUnspendablePolicyKey,
    );
    if (minimumVersion == null) return;
    final currentVersion = await _datasource.getBitcoinAppVersion(device);
    if (_versionIsBefore(currentVersion, minimumVersion)) {
      throw LedgerError.operationFailed(
        message: 'LEDGER_ERROR_BITCOIN_APP_UPDATE_REQUIRED',
      );
    }
  }

  ({List<WalletDescriptorKey> policyKeys, bool hasUnspendablePolicyKey})
  _analyzePolicyDescriptor(Wallet wallet) =>
      _descriptorPort.analyzeBitcoinPolicyDescriptor(
        descriptor: wallet.publicDescriptor,
        network: wallet.network,
      );

  WalletPolicy _walletPolicy(
    Wallet wallet,
    List<WalletDescriptorKey> policyKeys,
  ) => LedgerWalletPolicyAdapter.fromWallet(
    wallet,
    descriptorPolicyKeys: policyKeys,
  );

  Future<Uint8List> _registeredHmac(
    String walletId,
    String signerId,
    String policyId,
  ) async {
    final hmac = await _hmacDatasource.get(
      walletId: walletId,
      signerId: signerId,
      policyId: policyId,
    );
    if (hmac == null) {
      throw LedgerError.operationFailed(
        message: 'LEDGER_ERROR_WALLET_POLICY_NOT_REGISTERED',
      );
    }
    return hmac;
  }

  Future<T> _executeWalletPolicyOperation<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on LedgerError {
      rethrow;
    } on FormatException {
      throw LedgerError.operationFailed(
        message: 'LEDGER_ERROR_UNSUPPORTED_WALLET_POLICY',
      );
    } on Exception catch (error) {
      final message = error.toString();
      if (message.contains('SW_DENIED_BY_USER')) {
        throw LedgerError.operationFailed(
          message: 'LEDGER_ERROR_REJECTED_BY_USER',
        );
      }
      if (message.contains('SW_INCORRECT_DATA') ||
          message.contains('SW_NOT_SUPPORTED')) {
        throw LedgerError.operationFailed(
          message: 'LEDGER_ERROR_UNSUPPORTED_WALLET_POLICY',
        );
      }
      throw LedgerError.operationFailed(message: 'LEDGER_ERROR_UNKNOWN');
    }
  }

  static void _ensureSupportedPolicy(Wallet wallet) {
    if (!wallet.supportsLedgerWalletPolicy) {
      throw LedgerError.operationFailed(
        message: 'LEDGER_ERROR_UNSUPPORTED_WALLET_POLICY',
      );
    }
  }

  static bool _sameXpub(String first, String second) =>
      Bip32Derivation.getBip32Xpub(first).toBase58() ==
      Bip32Derivation.getBip32Xpub(second).toBase58();

  static bool _versionIsBefore(String current, String minimum) {
    final currentParts = _versionParts(current);
    final minimumParts = _versionParts(minimum)!;
    if (currentParts == null) return true;
    for (var index = 0; index < minimumParts.length; index++) {
      if (currentParts[index] != minimumParts[index]) {
        return currentParts[index] < minimumParts[index];
      }
    }
    return false;
  }

  static List<int>? _versionParts(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) return null;
    return [for (var index = 1; index <= 3; index++) int.parse(match[index]!)];
  }

  @override
  Future<void> disconnectConnection(LedgerDeviceEntity device) async {
    final model = device.toModel();
    await _datasource.disconnectConnection(model);
  }

  @override
  Future<void> dispose() async {
    await _datasource.dispose();
  }
}
