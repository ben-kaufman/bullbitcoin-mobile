import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/send/domain/usecases/get_bitcoin_signing_plan_usecase.dart';

final class ResolvedBitcoinPolicy {
  final BitcoinSigningPlan signingPlan;
  final BitcoinPolicySelection selection;
  final BitcoinPolicyPath? path;
  final bool selectionAvailable;
  final bool canBuildTransaction;

  const ResolvedBitcoinPolicy({
    required this.signingPlan,
    required this.selection,
    required this.path,
    required this.selectionAvailable,
    required this.canBuildTransaction,
  });
}

class ResolveBitcoinPolicyUsecase {
  final GetBitcoinSigningPlanUsecase _getBitcoinSigningPlanUsecase;

  const ResolveBitcoinPolicyUsecase(this._getBitcoinSigningPlanUsecase);

  Future<ResolvedBitcoinPolicy> execute({
    required Wallet wallet,
    required BitcoinPolicySelection selection,
    required Set<String> selectedOutpoints,
    required Set<String> satisfiedHashlocks,
  }) async {
    var signingPlan = await _getBitcoinSigningPlanUsecase.execute(
      wallet: wallet,
      selection: selection,
    );
    final resolvedSelection = signingPlan.policy.selectOnlyAvailablePaths(
      current: selection,
      maturity: signingPlan.maturity,
      selectedOutpoints: selectedOutpoints,
    );
    signingPlan = BitcoinSigningPlan.fromPolicy(
      policy: signingPlan.policy,
      maturity: signingPlan.maturity,
      signers: wallet.signers,
      selection: resolvedSelection,
      signedDescriptorKeyIdsByKeychain:
          signingPlan.signedDescriptorKeyIdsByKeychain,
      inputKeychains: signingPlan.inputKeychains,
    );

    final selectionComplete = signingPlan.policy
        .pathRequirements(resolvedSelection)
        .isEmpty;
    final selectionAvailable = signingPlan.policy.selectionIsAvailable(
      selection: resolvedSelection,
      maturity: signingPlan.maturity,
      selectedOutpoints: selectedOutpoints,
    );
    final hasRequiredPreimages =
        selectionComplete &&
        signingPlan.policy
            .requiredHashlocks(resolvedSelection)
            .every(
              (hashlock) => satisfiedHashlocks.contains(
                '${hashlock.type.name}:${hashlock.hash.toLowerCase()}',
              ),
            );
    final canBuildTransaction =
        selectionComplete && selectionAvailable && hasRequiredPreimages;
    final path =
        canBuildTransaction &&
            (signingPlan.policy.requiresPath || signingPlan.policy.hasTimelock)
        ? signingPlan.policy.buildPath(
            resolvedSelection,
            maturity: signingPlan.maturity,
          )
        : null;

    return ResolvedBitcoinPolicy(
      signingPlan: signingPlan,
      selection: resolvedSelection,
      path: path,
      selectionAvailable: selectionAvailable,
      canBuildTransaction: canBuildTransaction,
    );
  }
}
