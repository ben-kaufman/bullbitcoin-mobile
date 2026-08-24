import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/utils/descriptor_derivation.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_facade.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/mappers/bitcoin_wallet_policy_mapper.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_descriptor_key_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_model.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bull_sdk/bdk.dart' as bdk;
import 'package:flutter_test/flutter_test.dart';

import '../../bdk_wallet_test_fixture.dart';

void main() {
  late List<SignerDescriptorKeys> signers;
  late String externalPublicDescriptor;
  late String internalPublicDescriptor;
  late BdkWalletDatasource datasource;

  setUpAll(() {
    signers = testMnemonics.map(deriveSignerKeys).toList();
    externalPublicDescriptor =
        DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
          threshold: 2,
          descriptorKeys: signers
              .map((signer) => signer.externalPublic)
              .toList(),
        );
    internalPublicDescriptor =
        DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
          threshold: 2,
          descriptorKeys: signers
              .map((signer) => signer.internalPublic)
              .toList(),
        );
  });

  setUp(() {
    datasource = BdkWalletDatasource();
  });

  BitcoinWalletPolicy analyzePolicy({required PublicBdkWalletModel wallet}) =>
      BitcoinWalletPolicyMapper.toEntity(
        datasource.analyzePolicy(wallet: wallet),
      );

  group('BdkWalletDatasource policy analysis', () {
    test('classifies mobile and external single-signature wallets', () {
      final descriptors = singleSignatureDescriptors(testMnemonics.first);
      final policy = analyzePolicy(
        wallet:
            WalletModel.publicBdk(
                  id: 'single-signature',
                  descriptor: twoPathDescriptor(
                    descriptors.external,
                    descriptors.internal,
                  ),
                  isTestnet: true,
                )
                as PublicBdkWalletModel,
      );
      final localPlan = BitcoinSigningPlan.fromPolicy(
        policy: policy,
        signers: [
          walletSigner(
            fingerprint: descriptors.fingerprint,
            xpub: descriptors.xpub,
            signer: SignerEntity.local,
          ),
        ],
      );
      final externalPlan = BitcoinSigningPlan.fromPolicy(
        policy: policy,
        signers: [
          walletSigner(
            fingerprint: descriptors.fingerprint,
            xpub: descriptors.xpub,
            signer: SignerEntity.remote,
          ),
        ],
      );

      expect(localPlan.canFinalizeLocally, isTrue);
      expect(localPlan.requiresExternalSigning, isFalse);
      expect(externalPlan.requiresExternalSigning, isTrue);
    });

    test('requires another signer when local keys are below the threshold', () {
      final policy = analyzePolicy(
        wallet:
            WalletModel.publicBdk(
                  id: 'multisig',
                  descriptor: twoPathDescriptor(
                    externalPublicDescriptor,
                    internalPublicDescriptor,
                  ),
                  isTestnet: true,
                )
                as PublicBdkWalletModel,
      );
      final oneLocalSigner = BitcoinSigningPlan.fromPolicy(
        policy: policy,
        signers: [
          for (final (index, signer) in signers.indexed)
            walletSigner(
              fingerprint: signer.fingerprint,
              xpub: signer.xpub,
              signer: index == 0 ? SignerEntity.local : SignerEntity.remote,
            ),
        ],
      );
      final twoLocalSigners = BitcoinSigningPlan.fromPolicy(
        policy: policy,
        signers: [
          for (final (index, signer) in signers.indexed)
            walletSigner(
              fingerprint: signer.fingerprint,
              xpub: signer.xpub,
              signer: index < 2 ? SignerEntity.local : SignerEntity.remote,
            ),
        ],
      );

      expect(policy.external.root, isA<BitcoinThresholdPolicyNode>());
      expect(oneLocalSigner.canFinalizeLocally, isFalse);
      expect(oneLocalSigner.requiresExternalSigning, isTrue);
      expect(twoLocalSigners.canFinalizeLocally, isTrue);
      expect(twoLocalSigners.requiresExternalSigning, isFalse);
    });

    test('maps Miniscript branches and relative timelocks', () {
      final externalDescriptor = bdk.Descriptor.newWsh(
        miniScript:
            'or_d(pk(${signers[0].externalPublic}),and_v(v:older(10),pk(${signers[1].externalPublic})))',
      ).toString();
      final internalDescriptor = bdk.Descriptor.newWsh(
        miniScript:
            'or_d(pk(${signers[0].internalPublic}),and_v(v:older(10),pk(${signers[1].internalPublic})))',
      ).toString();

      final policy = analyzePolicy(
        wallet:
            WalletModel.publicBdk(
                  id: 'miniscript',
                  descriptor: twoPathDescriptor(
                    externalDescriptor,
                    internalDescriptor,
                  ),
                  isTestnet: true,
                )
                as PublicBdkWalletModel,
      );

      expect(policy.requiresPath, isTrue);
      expect(
        containsPolicyNode<BitcoinRelativeTimelockPolicyNode>(
          policy.external.root,
        ),
        isTrue,
      );

      final selector = policy
          .pathSelectors(const BitcoinPolicySelection.empty())
          .single;
      final delayedIndex = selector.options.indexWhere(
        containsPolicyNode<BitcoinRelativeTimelockPolicyNode>,
      );
      final immediateIndex = selector.options.indexWhere(
        (option) =>
            !containsPolicyNode<BitcoinRelativeTimelockPolicyNode>(option),
      );
      final delayedSelection = policy.select(
        current: const BitcoinPolicySelection.empty(),
        requirement: selector,
        selectedIndices: {delayedIndex},
      );
      final immediateSelection = policy.select(
        current: const BitcoinPolicySelection.empty(),
        requirement: selector,
        selectedIndices: {immediateIndex},
      );
      final delayedPath = policy.buildPath(delayedSelection);

      expect(policy.pathRequirements(delayedSelection), isEmpty);
      expect(delayedPath.external, hasLength(1));
      expect(delayedPath.internal, hasLength(1));
      expect(delayedPath.requiresRelativeTimelock, isTrue);
      expect(
        policy.buildPath(immediateSelection).requiresRelativeTimelock,
        isFalse,
      );

      final plan = BitcoinSigningPlan.fromPolicy(
        policy: policy,
        selection: delayedSelection,
        signers: [
          walletSigner(
            fingerprint: signers[0].fingerprint,
            xpub: signers[0].xpub,
            signer: SignerEntity.local,
          ),
          walletSigner(
            fingerprint: signers[1].fingerprint,
            xpub: signers[1].xpub,
            signer: SignerEntity.remote,
          ),
        ],
      );
      expect(
        plan.requires(
          walletSigner(
            fingerprint: signers[0].fingerprint,
            xpub: signers[0].xpub,
            signer: SignerEntity.local,
          ),
        ),
        isFalse,
      );
      expect(
        bdk.Psbt(
          psbtBase64: buildUnsignedPsbt(
            descriptor: twoPathDescriptor(
              externalDescriptor,
              internalDescriptor,
            ),
            policyPath: delayedPath,
          ),
        ).extractTx().input().single.sequence,
        10,
      );
    });

    test('maps one signer account keys to distinct descriptor keys', () {
      final first = deriveSignerKeysAtAccount(testMnemonics.first, account: 0);
      final second = deriveSignerKeysAtAccount(testMnemonics.first, account: 1);
      final descriptor = twoPathDescriptor(
        'wsh(sortedmulti(2,${second.externalPublic},${first.externalPublic}))',
        'wsh(sortedmulti(2,${second.internalPublic},${first.internalPublic}))',
      );
      final parsed = BdkFacade.parsePublicTwoPathDescriptor(
        descriptor: descriptor,
        isTestnet: true,
      );
      final descriptorKeys = [
        for (final (index, key) in parsed.keys.indexed)
          WalletDescriptorKeyModel(
            id: 'key-$index',
            signerId: 'signer-0',
            masterFingerprint: key.masterFingerprint,
            xpubFingerprint: key.xpubFingerprint,
            xpub: key.xpub,
            derivationPath: key.derivationPath,
          ),
      ];

      final policy = BitcoinWalletPolicyMapper.toEntity(
        datasource.analyzePolicy(
          wallet:
              WalletModel.publicBdk(
                    id: 'repeated-key',
                    descriptor: descriptor,
                    isTestnet: true,
                  )
                  as PublicBdkWalletModel,
          descriptorKeys: descriptorKeys,
        ),
      );

      expect(parsed.keys, hasLength(2));
      expect(_signatureKeyValues(policy.external.root), ['key-0', 'key-1']);
    });

    test('decodes time-based relative timelocks', () {
      const oneTimeUnit = (1 << 22) + 1;
      final policy = analyzePolicy(
        wallet:
            WalletModel.publicBdk(
                  id: 'time-based-miniscript',
                  descriptor: twoPathDescriptor(
                    bdk.Descriptor.newWsh(
                      miniScript:
                          'and_v(v:older($oneTimeUnit),pk(${signers[0].externalPublic}))',
                    ).toString(),
                    bdk.Descriptor.newWsh(
                      miniScript:
                          'and_v(v:older($oneTimeUnit),pk(${signers[0].internalPublic}))',
                    ).toString(),
                  ),
                  isTestnet: true,
                )
                as PublicBdkWalletModel,
      );

      final timelock = findPolicyNode<BitcoinRelativeTimelockPolicyNode>(
        policy.external.root,
      );

      expect(timelock, isNotNull);
      expect(timelock!.type, BitcoinRelativeTimelockType.seconds);
      expect(timelock.value, 512);
    });
  });
}

List<String> _signatureKeyValues(BitcoinPolicyNode node) => switch (node) {
  BitcoinSignaturePolicyNode(:final key) => [key.value],
  BitcoinThresholdPolicyNode(:final children) => [
    for (final child in children) ..._signatureKeyValues(child),
  ],
  _ => const [],
};
