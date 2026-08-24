import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stops at the minimum signer set for a threshold policy', () {
    final signers = [
      _signer('aaaaaaaa', SignerEntity.local),
      _signer('bbbbbbbb', SignerEntity.remote),
      _signer('cccccccc', SignerEntity.remote),
    ];
    final policy = _thresholdPolicy(
      threshold: 2,
      keyIds: signers.map((signer) => signer.singleDescriptorKey!.id),
    );

    final unsigned = BitcoinSigningPlan.fromPolicy(
      policy: policy,
      signers: signers,
      inputKeychains: const {BitcoinPolicyKeychain.external},
    );
    final externalFirst = BitcoinSigningPlan.fromPolicy(
      policy: policy,
      signers: signers,
      signedDescriptorKeyIdsByKeychain: const {
        BitcoinPolicyKeychain.external: {'key-bbbbbbbb'},
      },
      inputKeychains: const {BitcoinPolicyKeychain.external},
    );
    final satisfied = BitcoinSigningPlan.fromPolicy(
      policy: policy,
      signers: signers,
      signedDescriptorKeyIdsByKeychain: const {
        BitcoinPolicyKeychain.external: {'key-bbbbbbbb', 'key-cccccccc'},
      },
      inputKeychains: const {BitcoinPolicyKeychain.external},
    );

    expect(unsigned.eligibleSigners, signers);
    expect(unsigned.signersNeeded, 2);
    expect(externalFirst.signersNeeded, 1);
    expect(satisfied.isSatisfied, isTrue);
    expect(satisfied.signersNeeded, 0);

    final groupedSigner = WalletSigner(
      id: 'signer-grouped',
      signer: SignerEntity.local,
      signerDevice: null,
      descriptorKeys: signers
          .take(2)
          .expand((signer) => signer.descriptorKeys)
          .map((key) => key.copyWith(signerId: 'signer-grouped'))
          .toList(),
    );
    final grouped = BitcoinSigningPlan.fromPolicy(
      policy: policy,
      signers: [groupedSigner, signers.last],
      inputKeychains: const {BitcoinPolicyKeychain.external},
    );

    expect(grouped.eligibleSigners, [groupedSigner, signers.last]);
    expect(grouped.signersNeeded, 1);
  });

  test('counts a Miniscript threshold path independently of path choice', () {
    final signers = [
      _signer('aaaaaaaa', SignerEntity.local),
      _signer('bbbbbbbb', SignerEntity.remote),
      _signer('cccccccc', SignerEntity.remote),
    ];
    final policy = _thresholdPolicy(
      threshold: 2,
      keyIds: signers.map((signer) => signer.singleDescriptorKey!.id),
      requiresPath: true,
    );
    final selector = policy
        .pathSelectors(const BitcoinPolicySelection.empty())
        .single;
    final selection = policy.select(
      current: const BitcoinPolicySelection.empty(),
      requirement: selector,
      selectedIndices: const {0, 1},
    );

    final plan = BitcoinSigningPlan.fromPolicy(
      policy: policy,
      selection: selection,
      signers: signers,
      signedDescriptorKeyIdsByKeychain: const {
        BitcoinPolicyKeychain.external: {'key-bbbbbbbb'},
      },
      inputKeychains: const {BitcoinPolicyKeychain.external},
    );

    expect(plan.eligibleSigners, signers.take(2));
    expect(plan.signersNeeded, 1);
    expect(plan.isSatisfied, isFalse);
  });

  test('tracks signatures for the keychain used by every input', () {
    final local = _signer('aaaaaaaa', SignerEntity.local);
    final remote = _signer('bbbbbbbb', SignerEntity.remote);
    final policy = BitcoinWalletPolicy(
      external: BitcoinSpendingPolicy(
        requiresPath: false,
        root: BitcoinSignaturePolicyNode(
          id: 'external',
          key: BitcoinPolicyKey(
            kind: BitcoinPolicyKeyKind.descriptorKey,
            value: local.singleDescriptorKey!.id,
          ),
        ),
      ),
      internal: BitcoinSpendingPolicy(
        requiresPath: false,
        root: BitcoinSignaturePolicyNode(
          id: 'internal',
          key: BitcoinPolicyKey(
            kind: BitcoinPolicyKeyKind.descriptorKey,
            value: remote.singleDescriptorKey!.id,
          ),
        ),
      ),
    );

    final plan = BitcoinSigningPlan.fromPolicy(
      policy: policy,
      signers: [local, remote],
      inputKeychains: const {BitcoinPolicyKeychain.external},
      signedDescriptorKeyIdsByKeychain: const {
        BitcoinPolicyKeychain.external: {'key-aaaaaaaa'},
      },
    );

    expect(plan.eligibleSigners, [local]);
    expect(plan.isSigned(local), isTrue);
    expect(plan.isSatisfied, isTrue);
  });

  test('requires a supplied preimage for a hashlock path', () {
    final signer = _signer('aaaaaaaa', SignerEntity.local);
    final spendingPolicy = BitcoinSpendingPolicy(
      requiresPath: false,
      root: BitcoinThresholdPolicyNode(
        id: 'and',
        threshold: 2,
        children: [
          BitcoinSignaturePolicyNode(
            id: 'signature',
            key: BitcoinPolicyKey(
              kind: BitcoinPolicyKeyKind.descriptorKey,
              value: signer.singleDescriptorKey!.id,
            ),
          ),
          BitcoinHashlockPolicyNode(
            id: 'hashlock',
            type: BitcoinHashlockType.sha256,
            hash: 'aa',
          ),
        ],
      ),
    );
    final policy = BitcoinWalletPolicy(
      external: spendingPolicy,
      internal: spendingPolicy,
    );
    BitcoinSigningPlan plan(Set<String> preimages) =>
        BitcoinSigningPlan.fromPolicy(
          policy: policy,
          signers: [signer],
          inputKeychains: const {BitcoinPolicyKeychain.external},
          signedDescriptorKeyIdsByKeychain: const {
            BitcoinPolicyKeychain.external: {'key-aaaaaaaa'},
          },
          satisfiedPreimageKeys: preimages,
        );

    expect(plan(const {}).isSatisfied, isFalse);
    expect(plan(const {'sha256:aa'}).isSatisfied, isTrue);
  });
}

WalletSigner _signer(String fingerprint, SignerEntity signer) =>
    WalletSigner.single(
      id: 'signer-$fingerprint',
      descriptorKeyId: 'key-$fingerprint',
      masterFingerprint: fingerprint,
      xpubFingerprint: fingerprint,
      xpub: 'tpub-$fingerprint',
      signer: signer,
      signerDevice: null,
    );

BitcoinWalletPolicy _thresholdPolicy({
  required int threshold,
  required Iterable<String> keyIds,
  bool requiresPath = false,
}) {
  BitcoinSpendingPolicy spendingPolicy() => BitcoinSpendingPolicy(
    requiresPath: requiresPath,
    root: BitcoinThresholdPolicyNode(
      id: 'threshold',
      threshold: threshold,
      requiresPath: requiresPath,
      children: [
        for (final keyId in keyIds)
          BitcoinSignaturePolicyNode(
            id: keyId,
            key: BitcoinPolicyKey(
              kind: BitcoinPolicyKeyKind.descriptorKey,
              value: keyId,
            ),
          ),
      ],
    ),
  );
  return BitcoinWalletPolicy(
    external: spendingPolicy(),
    internal: spendingPolicy(),
  );
}
