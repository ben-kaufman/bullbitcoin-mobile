import 'package:bb_mobile/core/utils/bitcoin_signer_result.dart' as core;
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/calculate_bitcoin_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/get_bitcoin_signing_plan_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_bitcoin_tx_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/verify_bitcoin_signed_transaction_usecase.dart';

enum BitcoinSignerResultKind { detect, psbt, transaction }

sealed class ProcessedBitcoinSignerResult {
  const ProcessedBitcoinSignerResult();
}

final class ProcessedBitcoinTransaction extends ProcessedBitcoinSignerResult {
  final String transaction;
  final int txSize;

  const ProcessedBitcoinTransaction({
    required this.transaction,
    required this.txSize,
  });
}

final class ProcessedBitcoinPsbt extends ProcessedBitcoinSignerResult {
  final String psbt;
  final bool isFinalized;
  final int txSize;
  final int absoluteFeesSat;
  final BitcoinSigningPlan signingPlan;

  const ProcessedBitcoinPsbt({
    required this.psbt,
    required this.isFinalized,
    required this.txSize,
    required this.absoluteFeesSat,
    required this.signingPlan,
  });
}

class ProcessBitcoinSignerResultUsecase {
  final SignBitcoinTxUsecase _signBitcoinTxUsecase;
  final GetBitcoinSigningPlanUsecase _getBitcoinSigningPlanUsecase;
  final CalculateBitcoinAbsoluteFeesUsecase
  _calculateBitcoinAbsoluteFeesUsecase;
  final VerifyBitcoinSignedTransactionUsecase
  _verifyBitcoinSignedTransactionUsecase;

  const ProcessBitcoinSignerResultUsecase({
    required this._signBitcoinTxUsecase,
    required this._getBitcoinSigningPlanUsecase,
    required this._calculateBitcoinAbsoluteFeesUsecase,
    required this._verifyBitcoinSignedTransactionUsecase,
  });

  Future<ProcessedBitcoinSignerResult> execute({
    required String result,
    required BitcoinSignerResultKind kind,
    required String currentPsbt,
    required Wallet? wallet,
    required BitcoinPolicySelection selection,
  }) async {
    final parsed = switch (kind) {
      BitcoinSignerResultKind.detect => core.parseBitcoinSignerResult(result),
      BitcoinSignerResultKind.psbt => (
        format: core.BitcoinSignerResultFormat.psbt,
        value: result,
      ),
      BitcoinSignerResultKind.transaction => (
        format: core.BitcoinSignerResultFormat.transaction,
        value: result,
      ),
    };
    return switch (parsed.format) {
      core.BitcoinSignerResultFormat.psbt => _processPsbt(
        psbt: parsed.value,
        currentPsbt: currentPsbt,
        wallet: wallet ?? (throw StateError('Wallet is required for a PSBT')),
        selection: selection,
      ),
      core.BitcoinSignerResultFormat.transaction => _processTransaction(
        transaction: parsed.value,
        currentPsbt: currentPsbt,
      ),
    };
  }

  Future<ProcessedBitcoinTransaction> _processTransaction({
    required String transaction,
    required String currentPsbt,
  }) async {
    final verified = await _verifyBitcoinSignedTransactionUsecase.execute(
      psbt: currentPsbt,
      transaction: transaction,
    );
    return ProcessedBitcoinTransaction(
      transaction: verified.transaction,
      txSize: verified.txSize,
    );
  }

  Future<ProcessedBitcoinPsbt> _processPsbt({
    required String psbt,
    required String currentPsbt,
    required Wallet wallet,
    required BitcoinPolicySelection selection,
  }) async {
    final signingResult = await _signBitcoinTxUsecase.execute(
      psbt: currentPsbt,
      externalPsbt: psbt,
      walletId: wallet.id,
      requireFinalized: false,
      tryFinalize: false,
    );
    final signingPlan = await _getBitcoinSigningPlanUsecase.execute(
      wallet: wallet,
      psbt: signingResult.signedPsbt,
      selection: selection,
    );
    final absoluteFeesSat = await _calculateBitcoinAbsoluteFeesUsecase.execute(
      psbt: signingResult.signedPsbt,
    );
    final finalized = signingPlan.isSatisfied
        ? await _signBitcoinTxUsecase.finalize(signingResult.signedPsbt)
        : (psbt: signingResult.signedPsbt, isFinalized: false);
    if (signingPlan.isSatisfied && !finalized.isFinalized) {
      throw StateError('The satisfied PSBT could not be finalized');
    }
    return ProcessedBitcoinPsbt(
      psbt: finalized.psbt,
      isFinalized: finalized.isFinalized,
      txSize: signingResult.txSize,
      absoluteFeesSat: absoluteFeesSat,
      signingPlan: signingPlan,
    );
  }
}
