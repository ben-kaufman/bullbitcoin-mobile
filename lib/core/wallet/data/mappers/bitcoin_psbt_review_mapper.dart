import 'package:bb_mobile/core/wallet/data/models/bitcoin_psbt_review_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_descriptor_key_model.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_psbt_review.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';

class BitcoinPsbtReviewMapper {
  static BitcoinPsbtReview toEntity(
    BitcoinPsbtReviewModel model, {
    required List<WalletDescriptorKeyModel> descriptorKeys,
    required Set<String> localSignerIds,
  }) => BitcoinPsbtReview(
    transactionId: model.transactionId,
    inputs: [
      for (final input in model.inputs)
        _inputToEntity(
          input,
          descriptorKeys: descriptorKeys,
          localSignerIds: localSignerIds,
        ),
    ],
    outputs: [
      for (final output in model.outputs)
        BitcoinPsbtOutputReview(
          index: output.index,
          amountSat: output.amountSat,
          address: output.address,
          scriptHex: output.scriptHex,
          isWalletOwned: output.isWalletOwned,
        ),
    ],
    feeSat: model.feeSat,
    estimatedTransactionVsize: model.estimatedTransactionVsize,
    lockTime: model.lockTime,
    version: model.version,
  );

  static BitcoinPsbtInputReview _inputToEntity(
    BitcoinPsbtInputReviewRecord input, {
    required List<WalletDescriptorKeyModel> descriptorKeys,
    required Set<String> localSignerIds,
  }) {
    final originKeyIds = _resolveKeyIds(input.originKeySources, descriptorKeys);
    final signedKeyIds = _resolveKeyIds(input.signedKeySources, descriptorKeys);
    return BitcoinPsbtInputReview(
      outpoint: input.outpoint,
      amountSat: input.amountSat,
      keychain: input.keychain,
      hasLocalSignerOrigin: descriptorKeys.any(
        (key) =>
            originKeyIds.contains(key.id) &&
            localSignerIds.contains(key.signerId),
      ),
      sequence: input.sequence,
      signedDescriptorKeyIds: signedKeyIds,
    );
  }

  static Set<String> _resolveKeyIds(
    List<BitcoinPsbtKeySourceRecord> sources,
    List<WalletDescriptorKeyModel> keys,
  ) => Set.unmodifiable({
    for (final source in sources)
      for (final key in keys)
        if (_matches(source, key)) key.id,
  });

  static bool _matches(
    BitcoinPsbtKeySourceRecord source,
    WalletDescriptorKeyModel key,
  ) {
    final publicKey = source.publicKey.toLowerCase();
    if (key.xpub.toLowerCase() == publicKey) return true;
    if (key.xpub.isEmpty) return false;

    final sourceFingerprint = source.fingerprint?.toLowerCase();
    final masterFingerprint = key.masterFingerprint.toLowerCase();
    final xpubFingerprint = key.xpubFingerprint.toLowerCase();
    if (masterFingerprint.isNotEmpty &&
        sourceFingerprint != masterFingerprint) {
      return false;
    }
    if (masterFingerprint.isEmpty &&
        xpubFingerprint.isNotEmpty &&
        sourceFingerprint != xpubFingerprint) {
      return false;
    }

    final sourcePath = _pathParts(source.derivationPath);
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
      return derived.public.toHexString().toLowerCase() == publicKey;
    } on Exception {
      return false;
    }
  }

  static List<String> _pathParts(String? path) {
    if (path == null || path.isEmpty || path == 'm') return const [];
    return path
        .replaceAllMapped(RegExp(r'(\d+)[hH]'), (match) => "${match[1]}'")
        .split('/')
        .where((part) => part.isNotEmpty && part != 'm')
        .toList();
  }

  static bool _startsWith(List<String> path, List<String> prefix) {
    if (path.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (path[index] != prefix[index]) return false;
    }
    return true;
  }
}
