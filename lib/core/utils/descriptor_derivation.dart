import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bull_sdk/bdk.dart' as bdk;
import 'package:bull_sdk/lwk.dart' as lwk;

class DescriptorDerivation {
  static String derivePublicBitcoinMultipathDescriptorFromXpub(
    String xpub, {
    required ScriptType scriptType,
    required bool isTestnet,
    String? masterFingerprint,
    String? derivationPath,
  }) {
    if ((masterFingerprint == null) != (derivationPath == null)) {
      throw ArgumentError(
        'masterFingerprint and derivationPath must be provided together',
      );
    }

    final accountKey = Bip32Derivation.getBip32Xpub(xpub);
    final canonicalXpub = accountKey.convert(
      isTestnet ? XpubType.tpub : XpubType.xpub,
    );
    final origin = masterFingerprint == null
        ? ''
        : '[${masterFingerprint.toLowerCase()}/${_withoutMasterPrefix(derivationPath!)}]';
    final descriptorKey = '$origin$canonicalXpub/<0;1>/*';
    final descriptorString = switch (scriptType) {
      ScriptType.bip84 => 'wpkh($descriptorKey)',
      ScriptType.bip49 => 'sh(wpkh($descriptorKey))',
      ScriptType.bip44 => 'pkh($descriptorKey)',
    };
    final descriptor = bdk.Descriptor(
      descriptor: descriptorString,
      networkKind: isTestnet ? bdk.NetworkKind.test : bdk.NetworkKind.main,
    );
    descriptor.sanityCheck();
    return descriptor.toString();
  }

  static String derivePublicBitcoinSortedMultisigDescriptor({
    required int threshold,
    required List<String> descriptorKeys,
  }) {
    final keys = descriptorKeys.map((key) => key.trim()).toList();
    if (keys.length < 2) {
      throw ArgumentError.value(
        descriptorKeys,
        'descriptorKeys',
        'multisig requires at least two keys',
      );
    }
    if (keys.any((key) => key.isEmpty)) {
      throw ArgumentError.value(
        descriptorKeys,
        'descriptorKeys',
        'keys must not be empty',
      );
    }
    if (keys.toSet().length != keys.length) {
      throw ArgumentError.value(
        descriptorKeys,
        'descriptorKeys',
        'keys must be unique',
      );
    }
    if (threshold < 1 || threshold > keys.length) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'must be between one and the number of keys',
      );
    }

    final descriptor = bdk.Descriptor.newWshSortedmulti(
      k: threshold,
      pks: keys,
    );
    descriptor.sanityCheck();
    return descriptor.toString();
  }

  static Future<String> derivePublicBitcoinDescriptorFromXpriv(
    String xprv, {
    required ScriptType scriptType,
    required bool isTestnet,
    bool isInternalKeychain = false,
  }) async {
    final secretKey = bdk.DescriptorSecretKey.fromString(privateKey: xprv);
    final networkKind = isTestnet ? bdk.NetworkKind.test : bdk.NetworkKind.main;
    final keychain = isInternalKeychain
        ? bdk.KeychainKind.internal
        : bdk.KeychainKind.external_;
    bdk.Descriptor descriptor;

    switch (scriptType) {
      case ScriptType.bip84:
        descriptor = bdk.Descriptor.newBip84(
          secretKey: secretKey,
          keychainKind: keychain,
          networkKind: networkKind,
        );
      case ScriptType.bip49:
        descriptor = bdk.Descriptor.newBip49(
          secretKey: secretKey,
          keychainKind: keychain,
          networkKind: networkKind,
        );
      case ScriptType.bip44:
        descriptor = bdk.Descriptor.newBip44(
          secretKey: secretKey,
          keychainKind: keychain,
          networkKind: networkKind,
        );
    }

    // `asString` returns the public descriptor.
    return descriptor.toString();
  }

  static Future<String> derivePublicLiquidDescriptorFromMnemonic(
    String mnemonic, {
    required ScriptType scriptType,
    required bool isTestnet,
  }) async {
    final lwk.Descriptor confidentialDescriptor =
        await lwk.Descriptor.newConfidential(
          network: isTestnet
              ? lwk.LiquidNetwork.testnet
              : lwk.LiquidNetwork.mainnet,
          mnemonic: mnemonic,
        );

    return confidentialDescriptor.ctDescriptor;
  }

  static String _withoutMasterPrefix(String derivationPath) =>
      derivationPath.startsWith('m/')
      ? derivationPath.substring(2)
      : derivationPath;
}
