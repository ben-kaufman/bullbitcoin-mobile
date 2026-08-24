import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_descriptor_key_model.dart';

bool walletDescriptorKeyMatches({
  required WalletDescriptorKeyModel key,
  required String publicKey,
  required String? fingerprint,
  required String? derivationPath,
  required bool isXOnly,
}) {
  final normalizedPublicKey = publicKey.toLowerCase();
  if (key.xpub.toLowerCase() == normalizedPublicKey) return true;
  if (key.xpub.isEmpty) return false;

  final normalizedFingerprint = fingerprint?.toLowerCase();
  final masterFingerprint = key.masterFingerprint.toLowerCase();
  final xpubFingerprint = key.xpubFingerprint.toLowerCase();
  if (masterFingerprint.isNotEmpty &&
      normalizedFingerprint != masterFingerprint) {
    return false;
  }
  if (masterFingerprint.isEmpty &&
      xpubFingerprint.isNotEmpty &&
      normalizedFingerprint != xpubFingerprint) {
    return false;
  }

  final sourcePath = _pathParts(derivationPath);
  final accountPath = _pathParts(key.derivationPath);
  if (accountPath.isNotEmpty && !_startsWith(sourcePath, accountPath)) {
    return false;
  }
  final suffix = accountPath.isEmpty
      ? sourcePath
      : sourcePath.sublist(accountPath.length);
  if (suffix.any((part) => part.endsWith("'"))) return false;

  try {
    var derived = Bip32Derivation.getBip32Xpub(key.xpub);
    if (suffix.isNotEmpty) derived = derived.derivePath(suffix.join('/'));
    final derivedPublicKey = derived.public.toHexString().toLowerCase();
    return isXOnly
        ? derivedPublicKey.substring(2) == normalizedPublicKey
        : derivedPublicKey == normalizedPublicKey;
  } on Exception {
    return false;
  }
}

List<String> _pathParts(String? path) {
  if (path == null || path.isEmpty || path == 'm') return const [];
  return path
      .replaceAllMapped(RegExp(r'(\d+)[hH]'), (match) => "${match[1]}'")
      .split('/')
      .where((part) => part.isNotEmpty && part != 'm')
      .toList();
}

bool _startsWith(List<String> path, List<String> prefix) {
  if (path.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (path[index] != prefix[index]) return false;
  }
  return true;
}
