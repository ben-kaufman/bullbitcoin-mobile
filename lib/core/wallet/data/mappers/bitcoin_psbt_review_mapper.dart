import 'package:bb_mobile/core/wallet/data/models/bitcoin_psbt_review_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_descriptor_key_model.dart';
import 'package:bb_mobile/core/wallet/data/mappers/wallet_descriptor_key_matcher.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_psbt_review.dart';

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
    final relevantOriginSources = input.originKeySources.where(
      (source) =>
          source.tapLeafHash == null ||
          input.tapLeafHashes.contains(source.tapLeafHash),
    );
    final originKeyIds = _resolveKeyIds(relevantOriginSources, descriptorKeys);
    final relevantSignedSources = input.signedKeySources.where(
      (source) =>
          source.tapLeafHash == null ||
          input.tapLeafHashes.contains(source.tapLeafHash),
    );
    final signedKeyIds = _resolveKeyIds(relevantSignedSources, descriptorKeys);
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
    Iterable<BitcoinPsbtKeySourceRecord> sources,
    List<WalletDescriptorKeyModel> keys,
  ) => Set.unmodifiable({
    for (final source in sources)
      for (final key in keys)
        if (walletDescriptorKeyMatches(
          key: key,
          publicKey: source.publicKey,
          fingerprint: source.fingerprint,
          derivationPath: source.derivationPath,
          isXOnly: source.isXOnly,
        ))
          key.id,
  });
}
