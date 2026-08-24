import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';

class GetBitcoinSigningPlanUsecase {
  final BitcoinSigningPort _bitcoinSigningPort;

  GetBitcoinSigningPlanUsecase(this._bitcoinSigningPort);

  Future<BitcoinSigningPlan> execute({
    required Wallet wallet,
    String? psbt,
    BitcoinPolicySelection selection = const BitcoinPolicySelection.empty(),
    Set<String> satisfiedPreimageKeys = const {},
  }) async {
    if (!wallet.isBitcoin) {
      throw ArgumentError.value(
        wallet.id,
        'wallet',
        'must be a Bitcoin wallet',
      );
    }
    final policy = await _bitcoinSigningPort.getPolicy(walletId: wallet.id);
    final review = psbt == null
        ? null
        : await _bitcoinSigningPort.reviewPsbt(
            psbt,
            walletId: wallet.id,
            requireLocalOrigin: false,
          );
    final maturity =
        policy.hasTimelock ||
            policy.requiresPath ||
            (review?.hasTimingConstraint ?? false)
        ? await _bitcoinSigningPort.getPolicyMaturity(
            walletId: wallet.id,
            includeTimeBasedLocks:
                policy.hasTimeBasedTimelock ||
                (review?.hasTimeBasedTimingConstraint ?? false),
          )
        : const BitcoinPolicyMaturity.empty();
    return BitcoinSigningPlan.fromPolicy(
      policy: policy,
      maturity: maturity,
      signers: wallet.signers,
      selection: selection,
      signedDescriptorKeyIdsByKeychain:
          review?.signedDescriptorKeyIdsByKeychain ?? const {},
      inputKeychains: review?.inputs
          .map((input) => input.keychain)
          .whereType<BitcoinPolicyKeychain>()
          .toSet(),
      satisfiedPreimageKeys: satisfiedPreimageKeys,
    );
  }
}
