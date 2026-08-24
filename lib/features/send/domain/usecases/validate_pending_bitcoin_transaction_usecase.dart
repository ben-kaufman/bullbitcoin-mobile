import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_psbt_review_exception.dart';
import 'package:bb_mobile/core/wallet/domain/unsupported_bitcoin_policy_path_exception.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_utxos_usecase.dart';
import 'package:bb_mobile/features/send/domain/pending_bitcoin_transaction.dart';
import 'package:bb_mobile/features/send/domain/send_failure.dart';
import 'package:bb_mobile/features/send/domain/usecases/get_bitcoin_signing_plan_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/verify_bitcoin_signed_transaction_usecase.dart';
import 'package:meta/meta.dart';

class ValidatePendingBitcoinTransactionUsecase {
  final GetWalletUsecase _getWalletUsecase;
  final GetWalletUtxosUsecase _getWalletUtxosUsecase;
  final BitcoinSigningPort _bitcoinSigningPort;
  final GetBitcoinSigningPlanUsecase _getBitcoinSigningPlanUsecase;
  final VerifyBitcoinSignedTransactionUsecase
  _verifyBitcoinSignedTransactionUsecase;

  const ValidatePendingBitcoinTransactionUsecase(
    this._getWalletUsecase,
    this._getWalletUtxosUsecase,
    this._bitcoinSigningPort,
    this._getBitcoinSigningPlanUsecase,
    this._verifyBitcoinSignedTransactionUsecase,
  );

  @useResult
  Future<Result<PendingBitcoinTransaction, SendFailure>> execute(
    PendingBitcoinTransaction transaction,
  ) async {
    if (transaction.isDraft) return Ok(transaction);
    try {
      final wallet = await _getWalletUsecase.execute(transaction.walletId);
      if (wallet == null || !wallet.isBitcoin) {
        return const Err(SendStoredTransactionInvalidFailure());
      }
      final psbt = transaction.psbt!;
      final review = await _bitcoinSigningPort.reviewPsbt(
        psbt,
        walletId: wallet.id,
        requireLocalOrigin: false,
      );
      final amountSat = BigInt.parse(transaction.amount);
      final matchingOutputs = review.outputs
          .where(
            (output) =>
                output.address == transaction.recipient &&
                output.amountSat == amountSat,
          )
          .toList(growable: false);
      if (matchingOutputs.length != 1) {
        return const Err(SendStoredTransactionInvalidFailure());
      }
      final recipientOutput = matchingOutputs.single;
      final unexpectedExternalOutput = recipientOutput.isWalletOwned
          ? review.recipients.isNotEmpty
          : review.recipients.length != 1 ||
                review.recipients.single.index != recipientOutput.index;
      if (unexpectedExternalOutput) {
        return const Err(SendStoredTransactionInvalidFailure());
      }
      final plan = await _getBitcoinSigningPlanUsecase.execute(
        wallet: wallet,
        psbt: psbt,
        selection: transaction.policySelection,
      );
      final policyReady =
          plan.policy.pathRequirements(transaction.policySelection).isEmpty &&
          plan.policy.selectionIsAvailable(
            selection: transaction.policySelection,
            maturity: plan.maturity,
            selectedOutpoints: review.outpoints,
          ) &&
          review.timingIsSatisfied(plan.maturity);
      final utxos = await _getWalletUtxosUsecase.execute(walletId: wallet.id);
      final availableOutpoints = {
        for (final utxo in utxos) '${utxo.txId}:${utxo.vout}',
      };
      final conflict = review.outpoints.any(
        (outpoint) => !availableOutpoints.contains(outpoint),
      );
      if (transaction.selectedOutpoints.isNotEmpty &&
          !_sameOutpoints(transaction.selectedOutpoints, review.outpoints)) {
        return const Err(SendStoredTransactionInvalidFailure());
      }
      if (transaction.finalTransaction case final finalTransaction?) {
        await _verifyBitcoinSignedTransactionUsecase.execute(
          psbt: psbt,
          transaction: finalTransaction,
        );
      }
      final finalized = await _bitcoinSigningPort.finalizePsbt(psbt);
      final ready =
          transaction.finalTransaction != null || finalized.isFinalized;
      return Ok(
        transaction.copyWith(
          psbt: finalized.psbt,
          stage: ready
              ? PendingBitcoinTransactionStage.readyToBroadcast
              : PendingBitcoinTransactionStage.needsSignatures,
          isConflict: conflict,
          isPolicyReady: policyReady,
          signersNeeded: ready ? 0 : plan.signersNeeded,
        ),
      );
    } on BitcoinPsbtReviewException {
      return const Err(SendStoredTransactionInvalidFailure());
    } on UnsupportedBitcoinPolicyPathException {
      return const Err(SendStoredTransactionInvalidFailure());
    } on FormatException {
      return const Err(SendStoredTransactionInvalidFailure());
    } on Exception catch (error) {
      return Err(SendUnexpectedFailure(error.runtimeType.toString()));
    }
  }
}

bool _sameOutpoints(Set<String> first, Set<String> second) =>
    first.length == second.length && first.containsAll(second);
