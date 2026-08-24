import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy_maturity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy_node.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy_path.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_wallet_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_descriptor_key.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';

final class BitcoinSigningPlan {
  final BitcoinWalletPolicy policy;
  final BitcoinPolicyMaturity maturity;
  final BitcoinPolicySelection selection;
  final bool canFinalizeLocally;
  final Set<String> signedDescriptorKeyIds;
  final Map<BitcoinPolicyKeychain, Set<String>>
  signedDescriptorKeyIdsByKeychain;
  final Set<BitcoinPolicyKeychain> inputKeychains;
  final Set<String> satisfiedPreimageKeys;
  final List<WalletSigner> eligibleSigners;

  const BitcoinSigningPlan({
    required this.policy,
    this.maturity = const BitcoinPolicyMaturity.empty(),
    this.selection = const BitcoinPolicySelection.empty(),
    required this.canFinalizeLocally,
    this.signedDescriptorKeyIds = const {},
    this.signedDescriptorKeyIdsByKeychain = const {},
    this.inputKeychains = const {
      BitcoinPolicyKeychain.external,
      BitcoinPolicyKeychain.internal,
    },
    this.satisfiedPreimageKeys = const {},
    this.eligibleSigners = const [],
  });

  factory BitcoinSigningPlan.fromPolicy({
    required BitcoinWalletPolicy policy,
    BitcoinPolicyMaturity maturity = const BitcoinPolicyMaturity.empty(),
    required List<WalletSigner> signers,
    BitcoinPolicySelection selection = const BitcoinPolicySelection.empty(),
    Map<BitcoinPolicyKeychain, Set<String>> signedDescriptorKeyIdsByKeychain =
        const {},
    Set<BitcoinPolicyKeychain>? inputKeychains,
    Set<String> satisfiedPreimageKeys = const {},
  }) {
    final selectionComplete = policy.pathRequirements(selection).isEmpty;
    final usedKeychains = inputKeychains == null || inputKeychains.isEmpty
        ? const {BitcoinPolicyKeychain.external, BitcoinPolicyKeychain.internal}
        : Set<BitcoinPolicyKeychain>.unmodifiable(inputKeychains);
    final requiredKeys = selectionComplete
        ? policy.signatureKeys(selection, keychains: usedKeychains)
        : const <BitcoinPolicyKey>[];
    final eligibleSigners = [
      for (final signer in signers)
        if (signer.descriptorKeys.any(
          (descriptorKey) =>
              requiredKeys.any((key) => key.matches(descriptorKey)),
        ))
          signer,
    ];
    final signedByKeychain = <BitcoinPolicyKeychain, Set<String>>{
      for (final keychain in usedKeychains)
        keychain: Set.unmodifiable(
          signedDescriptorKeyIdsByKeychain[keychain] ?? const {},
        ),
    };
    final allSignedKeyIds = {
      for (final keyIds in signedByKeychain.values) ...keyIds,
    };

    bool descriptorKeyIsSigned(
      WalletDescriptorKey descriptorKey,
      BitcoinPolicyKeychain keychain,
    ) => signedByKeychain[keychain]?.contains(descriptorKey.id) ?? false;
    bool keyIsLocalOrSigned(
      BitcoinPolicyKey key,
      BitcoinPolicyKeychain keychain,
    ) => eligibleSigners.any(
      (signer) => signer.descriptorKeys.any(
        (descriptorKey) =>
            key.matches(descriptorKey) &&
            (descriptorKeyIsSigned(descriptorKey, keychain) ||
                signer.signer == SignerEntity.local),
      ),
    );
    final canFinalizeLocally =
        selectionComplete &&
        usedKeychains.every(
          (keychain) => policy.canBeSatisfiedBy(
            selection: selection,
            keychains: {keychain},
            hasSignature: (key) => keyIsLocalOrSigned(key, keychain),
            hasPreimage: (hashlock) => satisfiedPreimageKeys.contains(
              '${hashlock.type.name}:${hashlock.hash.toLowerCase()}',
            ),
          ),
        );

    return BitcoinSigningPlan(
      policy: policy,
      maturity: maturity,
      selection: selection,
      canFinalizeLocally: canFinalizeLocally,
      signedDescriptorKeyIds: Set.unmodifiable(allSignedKeyIds),
      signedDescriptorKeyIdsByKeychain: Map.unmodifiable(signedByKeychain),
      inputKeychains: usedKeychains,
      satisfiedPreimageKeys: Set.unmodifiable(satisfiedPreimageKeys),
      eligibleSigners: List.unmodifiable(eligibleSigners),
    );
  }

  bool get isSatisfied =>
      policy.pathRequirements(selection).isEmpty &&
      inputKeychains.every(
        (keychain) => policy.canBeSatisfiedBy(
          selection: selection,
          keychains: {keychain},
          hasSignature: (key) => eligibleSigners.any(
            (signer) => signer.descriptorKeys.any(
              (descriptorKey) =>
                  key.matches(descriptorKey) &&
                  _isSignedOnKeychain(descriptorKey, keychain),
            ),
          ),
          hasPreimage: (hashlock) => satisfiedPreimageKeys.contains(
            '${hashlock.type.name}:${hashlock.hash.toLowerCase()}',
          ),
        ),
      );

  bool get requiresExternalSigning => !isSatisfied && !canFinalizeLocally;

  int get signersNeeded {
    if (isSatisfied) return 0;
    final solutions = _policySignerSets(
      policy: policy,
      selection: selection,
      signers: eligibleSigners,
      signedDescriptorKeyIdsByKeychain: signedDescriptorKeyIdsByKeychain,
      inputKeychains: inputKeychains,
    );
    if (solutions.isEmpty) return eligibleSigners.length;
    return solutions
        .map((solution) => solution.length)
        .reduce((smallest, count) => count < smallest ? count : smallest);
  }

  bool requires(WalletSigner signer) =>
      eligibleSigners.any((eligible) => eligible.id == signer.id);

  bool isSigned(WalletSigner signer) {
    final relevant = _relevantDescriptorKeys(
      policy: policy,
      selection: selection,
      signer: signer,
      keychains: inputKeychains,
    );
    return relevant.isNotEmpty &&
        relevant.every((entry) => _isSignedOnKeychain(entry.$1, entry.$2));
  }

  bool _isSignedOnKeychain(
    WalletDescriptorKey descriptorKey,
    BitcoinPolicyKeychain keychain,
  ) =>
      signedDescriptorKeyIdsByKeychain[keychain]?.contains(descriptorKey.id) ??
      false;
}

List<(WalletDescriptorKey, BitcoinPolicyKeychain)> _relevantDescriptorKeys({
  required BitcoinWalletPolicy policy,
  required BitcoinPolicySelection selection,
  required WalletSigner signer,
  required Set<BitcoinPolicyKeychain> keychains,
}) => [
  for (final keychain in keychains)
    for (final descriptorKey in signer.descriptorKeys)
      if (policy
          .signatureKeys(selection, keychains: {keychain})
          .any((key) => key.matches(descriptorKey)))
        (descriptorKey, keychain),
];

List<Set<String>> _policySignerSets({
  required BitcoinWalletPolicy policy,
  required BitcoinPolicySelection selection,
  required List<WalletSigner> signers,
  required Map<BitcoinPolicyKeychain, Set<String>>
  signedDescriptorKeyIdsByKeychain,
  required Set<BitcoinPolicyKeychain> inputKeychains,
}) {
  var solutions = <Set<String>>[<String>{}];
  for (final keychain in inputKeychains) {
    solutions = _mergeSignerSets(
      solutions,
      _nodeSignerSets(
        node: switch (keychain) {
          BitcoinPolicyKeychain.external => policy.external.root,
          BitcoinPolicyKeychain.internal => policy.internal.root,
        },
        keychain: keychain,
        nodePath: 'root',
        selection: selection,
        signers: signers,
        signedDescriptorKeyIds:
            signedDescriptorKeyIdsByKeychain[keychain] ?? const {},
      ),
    );
  }
  return solutions;
}

List<Set<String>> _nodeSignerSets({
  required BitcoinPolicyNode node,
  required BitcoinPolicyKeychain keychain,
  required String nodePath,
  required BitcoinPolicySelection selection,
  required List<WalletSigner> signers,
  required Set<String> signedDescriptorKeyIds,
}) {
  if (node is BitcoinSignaturePolicyNode) {
    final matching = [
      for (final signer in signers)
        for (final descriptorKey in signer.descriptorKeys)
          if (node.key.matches(descriptorKey)) (signer, descriptorKey),
    ];
    if (matching.any((match) => signedDescriptorKeyIds.contains(match.$2.id))) {
      return [<String>{}];
    }
    return _minimalSignerSets([
      for (final match in matching) {match.$1.id},
    ]);
  }
  if (node is! BitcoinThresholdPolicyNode) return [<String>{}];

  final selected = node.requiresSelection
      ? selection.choiceFor(keychain: keychain, nodePath: nodePath)
      : null;
  final childIndices = selected ?? Iterable.generate(node.children.length);
  final combinations = List.generate(node.threshold + 1, (_) => <Set<String>>[])
    ..[0].add(<String>{});
  for (final index in childIndices) {
    final childSets = _nodeSignerSets(
      node: node.children[index],
      keychain: keychain,
      nodePath: '$nodePath/$index',
      selection: selection,
      signers: signers,
      signedDescriptorKeyIds: signedDescriptorKeyIds,
    );
    for (var count = node.threshold - 1; count >= 0; count--) {
      if (combinations[count].isEmpty || childSets.isEmpty) continue;
      combinations[count + 1] = _minimalSignerSets([
        ...combinations[count + 1],
        for (final existing in combinations[count])
          for (final child in childSets) {...existing, ...child},
      ]);
    }
  }
  return combinations[node.threshold];
}

List<Set<String>> _mergeSignerSets(
  List<Set<String>> first,
  List<Set<String>> second,
) {
  if (first.isEmpty || second.isEmpty) return const [];
  return _minimalSignerSets([
    for (final left in first)
      for (final right in second) {...left, ...right},
  ]);
}

List<Set<String>> _minimalSignerSets(Iterable<Set<String>> candidates) {
  final ordered = candidates.toList()
    ..sort((first, second) => first.length.compareTo(second.length));
  final minimal = <Set<String>>[];
  for (final candidate in ordered) {
    if (minimal.any(candidate.containsAll)) continue;
    minimal.add(Set.unmodifiable(candidate));
  }
  return List.unmodifiable(minimal);
}
