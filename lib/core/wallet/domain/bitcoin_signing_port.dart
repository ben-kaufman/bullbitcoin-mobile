import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_psbt_review.dart';

abstract interface class BitcoinSigningPort {
  Future<BitcoinWalletPolicy> getPolicy({required String walletId});

  Future<BitcoinPolicyMaturity> getPolicyMaturity({
    required String walletId,
    required bool includeTimeBasedLocks,
  });

  Future<({String psbt, bool isFinalized})> signPsbt(
    String psbt, {
    required String walletId,
    bool tryFinalize = true,
    String? signerId,
  });

  Future<BitcoinPsbtReview> reviewPsbt(
    String psbt, {
    required String walletId,
    bool requireLocalOrigin = true,
  });

  Future<({String psbt, bool isFinalized})> combinePsbts({
    required String currentPsbt,
    required String signedPsbt,
    required String walletId,
    bool tryFinalize = true,
  });

  Future<({String psbt, bool isFinalized})> finalizePsbt(String psbt);

  Future<bool> validatePolicyPreimage(BitcoinPolicyPreimage preimage);

  Future<String> applyPolicyPreimages({
    required String psbt,
    required List<BitcoinPolicyPreimage> preimages,
  });

  Future<({String transaction, int txSize})> verifyFinalTransaction({
    required String psbt,
    required String transaction,
  });

  Future<int> getTxSize({required String psbt, required String walletId});
}
