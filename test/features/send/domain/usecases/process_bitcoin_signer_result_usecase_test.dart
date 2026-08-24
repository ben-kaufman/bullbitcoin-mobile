import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/calculate_bitcoin_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/get_bitcoin_signing_plan_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/process_bitcoin_signer_result_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_bitcoin_tx_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/verify_bitcoin_signed_transaction_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

const _transaction =
    '020000000111111111111111111111111111111111111111111111111111111111'
    '111111110000000000fdffffff01a0860100000000001600142222222222222222'
    '22222222222222222222222200000000';

class _MockSignBitcoinTxUsecase extends Mock implements SignBitcoinTxUsecase {}

class _MockGetBitcoinSigningPlanUsecase extends Mock
    implements GetBitcoinSigningPlanUsecase {}

class _MockCalculateBitcoinAbsoluteFeesUsecase extends Mock
    implements CalculateBitcoinAbsoluteFeesUsecase {}

class _MockVerifyBitcoinSignedTransactionUsecase extends Mock
    implements VerifyBitcoinSignedTransactionUsecase {}

void main() {
  late _MockSignBitcoinTxUsecase signBitcoin;
  late _MockGetBitcoinSigningPlanUsecase getSigningPlan;
  late _MockCalculateBitcoinAbsoluteFeesUsecase calculateFees;
  late _MockVerifyBitcoinSignedTransactionUsecase verifyTransaction;
  late ProcessBitcoinSignerResultUsecase usecase;

  setUp(() {
    signBitcoin = _MockSignBitcoinTxUsecase();
    getSigningPlan = _MockGetBitcoinSigningPlanUsecase();
    calculateFees = _MockCalculateBitcoinAbsoluteFeesUsecase();
    verifyTransaction = _MockVerifyBitcoinSignedTransactionUsecase();
    usecase = ProcessBitcoinSignerResultUsecase(
      signBitcoinTxUsecase: signBitcoin,
      getBitcoinSigningPlanUsecase: getSigningPlan,
      calculateBitcoinAbsoluteFeesUsecase: calculateFees,
      verifyBitcoinSignedTransactionUsecase: verifyTransaction,
    );
  });

  test(
    'detects and verifies a final transaction against the prepared PSBT',
    () async {
      when(
        () => verifyTransaction.execute(
          psbt: 'current-psbt',
          transaction: _transaction,
        ),
      ).thenAnswer(
        (_) async => (transaction: 'verified-transaction', txSize: 123),
      );

      final result = await usecase.execute(
        result: _transaction,
        kind: BitcoinSignerResultKind.detect,
        currentPsbt: 'current-psbt',
        wallet: _wallet(),
        selection: const BitcoinPolicySelection.empty(),
      );

      expect(result, isA<ProcessedBitcoinTransaction>());
      final transaction = result as ProcessedBitcoinTransaction;
      expect(transaction.transaction, 'verified-transaction');
      expect(transaction.txSize, 123);
    },
  );

  test('combines and reviews a partial PSBT', () async {
    final wallet = _wallet();
    final signingPlan = BitcoinSigningPlan.fromPolicy(
      policy: _policy(),
      signers: wallet.signers,
    );
    when(
      () => signBitcoin.execute(
        psbt: 'current-psbt',
        walletId: wallet.id,
        externalPsbt: 'external-psbt',
        requireFinalized: false,
        tryFinalize: false,
      ),
    ).thenAnswer(
      (_) async =>
          (signedPsbt: 'combined-psbt', txSize: 234, isFinalized: false),
    );
    when(
      () => getSigningPlan.execute(
        wallet: wallet,
        psbt: 'combined-psbt',
        selection: const BitcoinPolicySelection.empty(),
      ),
    ).thenAnswer((_) async => signingPlan);
    when(
      () => calculateFees.execute(psbt: 'combined-psbt'),
    ).thenAnswer((_) async => 1000);

    final result = await usecase.execute(
      result: 'external-psbt',
      kind: BitcoinSignerResultKind.psbt,
      currentPsbt: 'current-psbt',
      wallet: wallet,
      selection: const BitcoinPolicySelection.empty(),
    );

    expect(result, isA<ProcessedBitcoinPsbt>());
    final psbt = result as ProcessedBitcoinPsbt;
    expect(psbt.psbt, 'combined-psbt');
    expect(psbt.isFinalized, isFalse);
    expect(psbt.txSize, 234);
    expect(psbt.absoluteFeesSat, 1000);
    expect(psbt.signingPlan, same(signingPlan));
  });

  test('finalizes as soon as the returned PSBT satisfies the policy', () async {
    final wallet = _wallet();
    final signingPlan = BitcoinSigningPlan.fromPolicy(
      policy: _policy(),
      signers: wallet.signers,
      signedDescriptorKeyIdsByKeychain: const {
        BitcoinPolicyKeychain.external: {'key-0'},
      },
      inputKeychains: const {BitcoinPolicyKeychain.external},
    );
    when(
      () => signBitcoin.execute(
        psbt: 'current-psbt',
        walletId: wallet.id,
        externalPsbt: 'external-psbt',
        requireFinalized: false,
        tryFinalize: false,
      ),
    ).thenAnswer(
      (_) async =>
          (signedPsbt: 'combined-psbt', txSize: 234, isFinalized: false),
    );
    when(
      () => getSigningPlan.execute(
        wallet: wallet,
        psbt: 'combined-psbt',
        selection: const BitcoinPolicySelection.empty(),
      ),
    ).thenAnswer((_) async => signingPlan);
    when(
      () => signBitcoin.finalize('combined-psbt'),
    ).thenAnswer((_) async => (psbt: 'final-psbt', isFinalized: true));
    when(
      () => calculateFees.execute(psbt: 'combined-psbt'),
    ).thenAnswer((_) async => 1000);

    final result = await usecase.execute(
      result: 'external-psbt',
      kind: BitcoinSignerResultKind.psbt,
      currentPsbt: 'current-psbt',
      wallet: wallet,
      selection: const BitcoinPolicySelection.empty(),
    );

    final psbt = result as ProcessedBitcoinPsbt;
    expect(psbt.psbt, 'final-psbt');
    expect(psbt.isFinalized, isTrue);
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

BitcoinWalletPolicy _policy() {
  BitcoinSpendingPolicy spendingPolicy() => BitcoinSpendingPolicy(
    requiresPath: false,
    root: BitcoinSignaturePolicyNode(
      id: 'local',
      key: BitcoinPolicyKey(
        kind: BitcoinPolicyKeyKind.fingerprint,
        value: 'aabbccdd',
      ),
    ),
  );
  return BitcoinWalletPolicy(
    external: spendingPolicy(),
    internal: spendingPolicy(),
  );
}
