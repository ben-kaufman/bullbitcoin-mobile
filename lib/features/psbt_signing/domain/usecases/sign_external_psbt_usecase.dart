import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_psbt_review_exception.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/features/psbt_signing/domain/psbt_signing_failure.dart';
import 'package:bb_mobile/features/psbt_signing/domain/psbt_signing_review.dart';
import 'package:meta/meta.dart';

class SignExternalPsbtUsecase {
  final BitcoinSigningPort _bitcoinSigningPort;

  const SignExternalPsbtUsecase(this._bitcoinSigningPort);

  @useResult
  Future<Result<PsbtSigningResult, PsbtSigningFailure>> execute(
    PsbtSigningReview review,
  ) async {
    if (!review.canSign) {
      return const Err(PsbtSigningMissingLocalKeyFailure());
    }

    try {
      final signed = await _bitcoinSigningPort.signPsbt(
        review.psbt,
        walletId: review.wallet.id,
        tryFinalize: false,
      );
      final transaction = await _bitcoinSigningPort.reviewPsbt(
        signed.psbt,
        walletId: review.wallet.id,
      );
      if (transaction.transactionId != review.transaction.transactionId) {
        return const Err(PsbtSigningWalletMismatchFailure());
      }

      final localKeyIds = review.wallet.signers
          .where((signer) => signer.signer == SignerEntity.local)
          .expand((signer) => signer.descriptorKeys)
          .map((key) => key.id)
          .toSet();
      var addedKeyIds = transaction.signedDescriptorKeyIds
          .difference(review.transaction.signedDescriptorKeyIds)
          .intersection(localKeyIds);
      if (addedKeyIds.isEmpty && signed.isFinalized) {
        addedKeyIds = localKeyIds.difference(
          review.transaction.signedDescriptorKeyIds,
        );
      }
      if (addedKeyIds.isEmpty) {
        return const Err(PsbtSigningNoSignatureAddedFailure());
      }

      return Ok(
        PsbtSigningResult(psbt: signed.psbt, isFinalized: signed.isFinalized),
      );
    } on InvalidBitcoinPsbtException {
      return const Err(PsbtSigningInvalidPsbtFailure());
    } on BitcoinPsbtWalletMismatchException {
      return const Err(PsbtSigningWalletMismatchFailure());
    } on BitcoinPsbtMissingLocalOriginException {
      return const Err(PsbtSigningMissingLocalKeyFailure());
    } on BitcoinPsbtMissingUtxoException {
      return const Err(PsbtSigningMissingUtxoFailure());
    } on BitcoinPsbtUnsupportedSighashException {
      return const Err(PsbtSigningUnsupportedSighashFailure());
    } on Exception catch (error, stackTrace) {
      log.severe(
        message: 'Failed to sign external PSBT',
        error: error.runtimeType,
        trace: stackTrace,
      );
      return const Err(PsbtSigningUnexpectedFailure());
    }
  }
}
