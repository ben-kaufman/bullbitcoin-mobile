import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_psbt_review.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_bitcoin_tx_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeBitcoinSigningPort implements BitcoinSigningPort {
  final ({String psbt, bool isFinalized}) signingResult;
  int signCalls = 0;
  int combineCalls = 0;

  _FakeBitcoinSigningPort(this.signingResult);

  @override
  Future<({String psbt, bool isFinalized})> combinePsbts({
    required String currentPsbt,
    required String signedPsbt,
    required String walletId,
    bool tryFinalize = true,
  }) async {
    combineCalls++;
    return signingResult;
  }

  @override
  Future<({String psbt, bool isFinalized})> finalizePsbt(String psbt) async =>
      signingResult;

  @override
  Future<BitcoinWalletPolicy> getPolicy({required String walletId}) =>
      throw UnimplementedError();

  @override
  Future<BitcoinPolicyMaturity> getPolicyMaturity({
    required String walletId,
    required bool includeTimeBasedLocks,
  }) => throw UnimplementedError();

  @override
  Future<BitcoinPsbtReview> reviewPsbt(
    String psbt, {
    required String walletId,
    bool requireLocalOrigin = true,
  }) => throw UnimplementedError();

  @override
  Future<int> getTxSize({
    required String psbt,
    required String walletId,
  }) async => 120;

  @override
  Future<String> applyPolicyPreimages({
    required String psbt,
    required List<BitcoinPolicyPreimage> preimages,
  }) => throw UnimplementedError();

  @override
  Future<bool> validatePolicyPreimage(BitcoinPolicyPreimage preimage) =>
      throw UnimplementedError();

  @override
  Future<({String transaction, int txSize})> verifyFinalTransaction({
    required String psbt,
    required String transaction,
  }) => throw UnimplementedError();

  @override
  Future<({bool isFinalized, String psbt})> signPsbt(
    String psbt, {
    required String walletId,
    bool tryFinalize = true,
    String? signerId,
  }) async {
    signCalls++;
    return signingResult;
  }
}

void main() {
  test('rejects a PSBT that is not fully signed by default', () {
    final usecase = SignBitcoinTxUsecase(
      _FakeBitcoinSigningPort((psbt: 'partial', isFinalized: false)),
    );

    expect(
      () => usecase.execute(psbt: 'unsigned', walletId: 'wallet'),
      throwsA(isA<SignBitcoinTxException>()),
    );
  });

  test(
    'returns a partial PSBT when the caller is coordinating signers',
    () async {
      final usecase = SignBitcoinTxUsecase(
        _FakeBitcoinSigningPort((psbt: 'partial', isFinalized: false)),
      );

      final result = await usecase.execute(
        psbt: 'unsigned',
        walletId: 'wallet',
        requireFinalized: false,
      );

      expect(result.signedPsbt, 'partial');
      expect(result.isFinalized, isFalse);
      expect(result.txSize, 120);
    },
  );

  test('combines a PSBT returned by an external signer', () async {
    final port = _FakeBitcoinSigningPort((psbt: 'combined', isFinalized: true));
    final usecase = SignBitcoinTxUsecase(port);

    final result = await usecase.execute(
      psbt: 'current',
      externalPsbt: 'external',
      walletId: 'wallet',
    );

    expect(result.signedPsbt, 'combined');
    expect(port.combineCalls, 1);
    expect(port.signCalls, 0);
  });
}
