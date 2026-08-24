import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/utils/bitcoin_signer_result.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_psbt_review_exception.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_usecase.dart';
import 'package:bb_mobile/features/psbt_signing/domain/psbt_signing_failure.dart';
import 'package:bb_mobile/features/psbt_signing/domain/psbt_signing_review.dart';
import 'package:meta/meta.dart';

class ReviewPsbtUsecase {
  final GetWalletUsecase _getWalletUsecase;
  final BitcoinSigningPort _bitcoinSigningPort;

  const ReviewPsbtUsecase({
    required this._getWalletUsecase,
    required this._bitcoinSigningPort,
  });

  @useResult
  Future<Result<PsbtSigningReview, PsbtSigningFailure>> execute({
    required String walletId,
    required String psbt,
  }) async {
    try {
      final wallet = await _getWalletUsecase.execute(walletId);
      if (wallet == null || !wallet.isBitcoin) {
        return const Err(PsbtSigningWalletUnavailableFailure());
      }
      if (!wallet.signers.any(
        (signer) => signer.signer == SignerEntity.local,
      )) {
        return const Err(PsbtSigningMissingLocalKeyFailure());
      }

      final normalizedPsbt = normalizeBitcoinPsbt(psbt);
      final transaction = await _bitcoinSigningPort.reviewPsbt(
        normalizedPsbt,
        walletId: walletId,
      );
      final policy = await _bitcoinSigningPort.getPolicy(walletId: walletId);
      final maturity = transaction.hasTimingConstraint
          ? await _bitcoinSigningPort.getPolicyMaturity(
              walletId: walletId,
              includeTimeBasedLocks: transaction.hasTimeBasedTimingConstraint,
            )
          : const BitcoinPolicyMaturity.empty();
      final transactionTimingVerified = transaction.timingIsSatisfied(maturity);
      final review = PsbtSigningReview(
        wallet: wallet,
        psbt: normalizedPsbt,
        transaction: transaction,
        policy: policy,
        transactionTimingVerified: transactionTimingVerified,
        blockingTimingActivation: transactionTimingVerified
            ? null
            : transaction.blockingTimingActivation(maturity),
      );
      return Ok(review);
    } on FormatException {
      return const Err(PsbtSigningInvalidPsbtFailure());
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
        message: 'Failed to review external PSBT',
        error: error.runtimeType,
        trace: stackTrace,
      );
      return const Err(PsbtSigningUnexpectedFailure());
    }
  }
}
