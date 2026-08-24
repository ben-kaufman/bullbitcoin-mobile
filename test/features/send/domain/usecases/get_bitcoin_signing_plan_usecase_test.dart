import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_psbt_review.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:bb_mobile/features/send/domain/usecases/get_bitcoin_signing_plan_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBitcoinSigningPort extends Mock implements BitcoinSigningPort {}

void main() {
  test(
    'loads maturity and existing signatures for a selectable policy',
    () async {
      final port = _MockBitcoinSigningPort();
      final wallet = _wallet();
      final policy = _policy();
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
        () => port.getPolicy(walletId: wallet.id),
      ).thenAnswer((_) async => policy);
      when(
        () => port.getPolicyMaturity(
          walletId: wallet.id,
          includeTimeBasedLocks: false,
        ),
      ).thenAnswer((_) async => maturity);
      when(
        () => port.reviewPsbt(
          'psbt',
          walletId: wallet.id,
          requireLocalOrigin: false,
        ),
      ).thenAnswer(
        (_) async => _review(
          signedDescriptorKeyIds: const {'key-0'},
          keychain: BitcoinPolicyKeychain.external,
        ),
      );

      final plan = await GetBitcoinSigningPlanUsecase(
        port,
      ).execute(wallet: wallet, psbt: 'psbt');

      expect(plan.policy, same(policy));
      expect(plan.maturity, same(maturity));
      expect(plan.signedDescriptorKeyIds, {'key-0'});
      verify(
        () => port.getPolicyMaturity(
          walletId: wallet.id,
          includeTimeBasedLocks: false,
        ),
      ).called(1);
    },
  );

  test('rejects a non-Bitcoin wallet before loading its policy', () async {
    final port = _MockBitcoinSigningPort();
    final wallet = _wallet(network: Network.liquidTestnet);

    expect(
      () => GetBitcoinSigningPlanUsecase(port).execute(wallet: wallet),
      throwsArgumentError,
    );
    verifyNever(() => port.getPolicy(walletId: any(named: 'walletId')));
  });

  test('loads maturity for a PSBT transaction-level timelock', () async {
    final port = _MockBitcoinSigningPort();
    final wallet = _wallet();
    final policy = _thresholdPolicy(
      threshold: 1,
      fingerprints: const ['aabbccdd'],
    );
    final maturity = BitcoinPolicyMaturity(
      tipHeight: 100,
      medianTimePast: null,
      utxos: [
        BitcoinPolicyUtxoMaturity(
          outpoint: '00:0',
          keychain: BitcoinPolicyKeychain.external,
          amountSat: BigInt.one,
          confirmations: 1,
        ),
      ],
    );
    when(
      () => port.getPolicy(walletId: wallet.id),
    ).thenAnswer((_) async => policy);
    when(
      () => port.reviewPsbt(
        'psbt',
        walletId: wallet.id,
        requireLocalOrigin: false,
      ),
    ).thenAnswer(
      (_) async => _review(
        signedDescriptorKeyIds: const {},
        keychain: BitcoinPolicyKeychain.external,
        lockTime: 100,
        sequence: 0xfffffffd,
      ),
    );
    when(
      () => port.getPolicyMaturity(
        walletId: wallet.id,
        includeTimeBasedLocks: false,
      ),
    ).thenAnswer((_) async => maturity);

    final plan = await GetBitcoinSigningPlanUsecase(
      port,
    ).execute(wallet: wallet, psbt: 'psbt');

    expect(plan.maturity, same(maturity));
    verify(
      () => port.getPolicyMaturity(
        walletId: wallet.id,
        includeTimeBasedLocks: false,
      ),
    ).called(1);
  });
}

BitcoinPsbtReview _review({
  required Set<String> signedDescriptorKeyIds,
  required BitcoinPolicyKeychain keychain,
  int lockTime = 0,
  int sequence = 0xffffffff,
}) => BitcoinPsbtReview(
  transactionId: '00',
  inputs: [
    BitcoinPsbtInputReview(
      outpoint: '00:0',
      amountSat: BigInt.zero,
      keychain: keychain,
      hasLocalSignerOrigin: true,
      sequence: sequence,
      signedDescriptorKeyIds: signedDescriptorKeyIds,
    ),
  ],
  outputs: [
    BitcoinPsbtOutputReview(
      index: 0,
      amountSat: BigInt.one,
      address: 'address',
      scriptHex: '00',
      isWalletOwned: false,
    ),
  ],
  feeSat: BigInt.zero,
  estimatedTransactionVsize: 1,
  lockTime: lockTime,
  version: 2,
);

Wallet _wallet({Network network = Network.bitcoinTestnet}) => Wallet(
  origin: 'wallet',
  network: network,
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

BitcoinWalletPolicy _thresholdPolicy({
  required int threshold,
  required Iterable<String> fingerprints,
  bool requiresPath = false,
}) {
  BitcoinSpendingPolicy spendingPolicy() => BitcoinSpendingPolicy(
    requiresPath: requiresPath,
    root: BitcoinThresholdPolicyNode(
      id: 'threshold',
      threshold: threshold,
      requiresPath: requiresPath,
      children: [
        for (final fingerprint in fingerprints)
          BitcoinSignaturePolicyNode(
            id: fingerprint,
            key: BitcoinPolicyKey(
              kind: BitcoinPolicyKeyKind.fingerprint,
              value: fingerprint,
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
