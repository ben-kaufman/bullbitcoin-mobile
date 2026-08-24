import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:bb_mobile/features/send/domain/usecases/get_bitcoin_signing_plan_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/resolve_bitcoin_policy_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetBitcoinSigningPlanUsecase extends Mock
    implements GetBitcoinSigningPlanUsecase {}

void main() {
  late _MockGetBitcoinSigningPlanUsecase getSigningPlan;
  late ResolveBitcoinPolicyUsecase usecase;

  setUp(() {
    getSigningPlan = _MockGetBitcoinSigningPlanUsecase();
    usecase = ResolveBitcoinPolicyUsecase(getSigningPlan);
  });

  test('selects the only available path and returns its BDK path', () async {
    final wallet = _wallet();
    final policy = _selectablePolicy();
    final maturity = BitcoinPolicyMaturity(
      tipHeight: 100,
      medianTimePast: null,
      utxos: [
        BitcoinPolicyUtxoMaturity(
          outpoint: '00:0',
          keychain: BitcoinPolicyKeychain.external,
          amountSat: BigInt.from(10000),
          confirmations: 1,
        ),
      ],
    );
    when(
      () => getSigningPlan.execute(
        wallet: wallet,
        selection: const BitcoinPolicySelection.empty(),
      ),
    ).thenAnswer(
      (_) async => BitcoinSigningPlan.fromPolicy(
        policy: policy,
        maturity: maturity,
        signers: wallet.signers,
      ),
    );

    final resolved = await usecase.execute(
      wallet: wallet,
      selection: const BitcoinPolicySelection.empty(),
      selectedOutpoints: const {'00:0'},
      satisfiedHashlocks: const {},
    );

    expect(resolved.canBuildTransaction, isTrue);
    expect(resolved.selectionAvailable, isTrue);
    expect(resolved.path, isNotNull);
    expect(
      resolved.selection.choiceFor(
        keychain: BitcoinPolicyKeychain.external,
        nodePath: 'root',
      ),
      [0],
    );
  });

  test('does not build an unavailable mandatory delayed path', () async {
    final wallet = _wallet();
    final policy = _mandatoryDelayedPolicy();
    final maturity = BitcoinPolicyMaturity(
      tipHeight: 100,
      medianTimePast: null,
      utxos: [
        BitcoinPolicyUtxoMaturity(
          outpoint: '00:0',
          keychain: BitcoinPolicyKeychain.external,
          amountSat: BigInt.from(10000),
          confirmations: 1,
        ),
      ],
    );
    when(
      () => getSigningPlan.execute(
        wallet: wallet,
        selection: const BitcoinPolicySelection.empty(),
      ),
    ).thenAnswer(
      (_) async => BitcoinSigningPlan.fromPolicy(
        policy: policy,
        maturity: maturity,
        signers: wallet.signers,
      ),
    );

    final resolved = await usecase.execute(
      wallet: wallet,
      selection: const BitcoinPolicySelection.empty(),
      selectedOutpoints: const {'00:0'},
      satisfiedHashlocks: const {},
    );

    expect(resolved.canBuildTransaction, isFalse);
    expect(resolved.selectionAvailable, isFalse);
    expect(resolved.path, isNull);
  });
}

Wallet _wallet() => Wallet(
  origin: 'wallet',
  network: Network.bitcoinTestnet,
  signers: [
    WalletSigner.single(
      masterFingerprint: 'aabbccdd',
      xpubFingerprint: 'aabbccdd',
      xpub: 'tpub-local',
      derivationPath: "m/48'/1'/0'/2'",
      signer: SignerEntity.local,
      signerDevice: null,
    ),
  ],
  scriptType: null,
  publicDescriptor: 'wsh(pk(...))',
  balanceSat: BigInt.zero,
);

BitcoinWalletPolicy _selectablePolicy() {
  final key = BitcoinPolicyKey(
    kind: BitcoinPolicyKeyKind.fingerprint,
    value: 'aabbccdd',
  );
  BitcoinSpendingPolicy spendingPolicy() => BitcoinSpendingPolicy(
    requiresPath: true,
    root: BitcoinThresholdPolicyNode(
      id: 'root',
      threshold: 1,
      requiresPath: true,
      children: [
        BitcoinSignaturePolicyNode(id: 'local', key: key),
        BitcoinAbsoluteTimelockPolicyNode(
          id: 'delay',
          type: BitcoinAbsoluteTimelockType.blockHeight,
          value: 200,
        ),
      ],
    ),
  );
  return BitcoinWalletPolicy(
    external: spendingPolicy(),
    internal: spendingPolicy(),
  );
}

BitcoinWalletPolicy _mandatoryDelayedPolicy() {
  final key = BitcoinPolicyKey(
    kind: BitcoinPolicyKeyKind.fingerprint,
    value: 'aabbccdd',
  );
  BitcoinSpendingPolicy spendingPolicy() => BitcoinSpendingPolicy(
    requiresPath: false,
    root: BitcoinThresholdPolicyNode(
      id: 'root',
      threshold: 2,
      children: [
        BitcoinSignaturePolicyNode(id: 'local', key: key),
        BitcoinRelativeTimelockPolicyNode(id: 'delay', value: 10),
      ],
    ),
  );
  return BitcoinWalletPolicy(
    external: spendingPolicy(),
    internal: spendingPolicy(),
  );
}
