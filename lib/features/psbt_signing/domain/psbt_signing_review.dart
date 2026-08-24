import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_psbt_review.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';

final class PsbtSigningReview {
  final Wallet wallet;
  final String psbt;
  final BitcoinPsbtReview transaction;
  final BitcoinWalletPolicy policy;
  final bool transactionTimingVerified;
  final BitcoinPolicyActivation? blockingTimingActivation;

  const PsbtSigningReview({
    required this.wallet,
    required this.psbt,
    required this.transaction,
    required this.policy,
    required this.transactionTimingVerified,
    this.blockingTimingActivation,
  });

  bool get canSign =>
      transaction.inputs.any((input) => input.hasLocalSignerOrigin);
}

final class PsbtSigningResult {
  final String psbt;
  final bool isFinalized;

  const PsbtSigningResult({required this.psbt, required this.isFinalized});
}
