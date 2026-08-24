import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/features/psbt_signing/domain/psbt_signing_failure.dart';
import 'package:bb_mobile/features/psbt_signing/domain/psbt_signing_review.dart';
import 'package:bb_mobile/features/psbt_signing/domain/usecases/sign_external_psbt_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../psbt_signing_test_fixture.dart';

class _MockBitcoinSigningPort extends Mock implements BitcoinSigningPort {}

void main() {
  test('returns the PSBT only after a local signature was added', () async {
    final port = _MockBitcoinSigningPort();
    final unsigned = psbtReview();
    final signed = psbtReview(signedDescriptorKeyIds: const {'key-local'});
    final review = psbtSigningReview(
      policy: singleLocalPolicy(),
      wallet: psbtSigningWallet(includeRemoteSigner: false),
      transaction: unsigned,
    );
    when(
      () => port.signPsbt('unsigned', walletId: 'wallet', tryFinalize: false),
    ).thenAnswer((_) async => (psbt: 'signed', isFinalized: false));
    when(
      () => port.reviewPsbt('signed', walletId: 'wallet'),
    ).thenAnswer((_) async => signed);

    final result = await SignExternalPsbtUsecase(port).execute(review);

    expect(result, isA<Ok<PsbtSigningResult, PsbtSigningFailure>>());
    final value = (result as Ok<PsbtSigningResult, PsbtSigningFailure>).value;
    expect(value.psbt, 'signed');
    expect(value.isFinalized, isFalse);
  });

  test('rejects a signing result without a new local signature', () async {
    final port = _MockBitcoinSigningPort();
    final transaction = psbtReview();
    final review = psbtSigningReview(
      policy: singleLocalPolicy(),
      wallet: psbtSigningWallet(includeRemoteSigner: false),
      transaction: transaction,
    );
    when(
      () => port.signPsbt('unsigned', walletId: 'wallet', tryFinalize: false),
    ).thenAnswer((_) async => (psbt: 'unchanged', isFinalized: false));
    when(
      () => port.reviewPsbt('unchanged', walletId: 'wallet'),
    ).thenAnswer((_) async => transaction);

    final result = await SignExternalPsbtUsecase(port).execute(review);

    expect(
      result,
      isA<Err<PsbtSigningResult, PsbtSigningFailure>>().having(
        (result) => result.failure,
        'failure',
        isA<PsbtSigningNoSignatureAddedFailure>(),
      ),
    );
  });
}
