import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/features/send/domain/usecases/validate_bitcoin_policy_preimage_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBitcoinSigningPort extends Mock implements BitcoinSigningPort {}

void main() {
  setUpAll(() => registerFallbackValue(_preimage(_repeat('00', 32))));

  test('normalizes and validates a hash preimage', () async {
    final port = _MockBitcoinSigningPort();
    when(
      () => port.validatePolicyPreimage(any()),
    ).thenAnswer((_) async => true);

    final result = await ValidateBitcoinPolicyPreimageUsecase(
      port,
    ).execute(hashlock: _hashlock(), preimageHex: '  ${_repeat('AABB', 16)}  ');

    expect(result, _preimage(_repeat('aabb', 16)));
    verify(
      () => port.validatePolicyPreimage(_preimage(_repeat('aabb', 16))),
    ).called(1);
  });

  test('rejects malformed hex without calling the signing port', () async {
    final port = _MockBitcoinSigningPort();

    final result = await ValidateBitcoinPolicyPreimageUsecase(
      port,
    ).execute(hashlock: _hashlock(), preimageHex: 'not hex');

    expect(result, isNull);
    verifyNever(() => port.validatePolicyPreimage(any()));
  });

  test('rejects preimages that are not 32 bytes', () async {
    final port = _MockBitcoinSigningPort();
    final usecase = ValidateBitcoinPolicyPreimageUsecase(port);

    expect(
      await usecase.execute(
        hashlock: _hashlock(),
        preimageHex: _repeat('00', 31),
      ),
      isNull,
    );
    expect(
      await usecase.execute(
        hashlock: _hashlock(),
        preimageHex: _repeat('00', 33),
      ),
      isNull,
    );
    verifyNever(() => port.validatePolicyPreimage(any()));
  });
}

BitcoinHashlockPolicyNode _hashlock() => BitcoinHashlockPolicyNode(
  id: 'hashlock',
  type: BitcoinHashlockType.sha256,
  hash: List.filled(32, '11').join(),
);

BitcoinPolicyPreimage _preimage(String value) => BitcoinPolicyPreimage(
  type: BitcoinHashlockType.sha256,
  hash: List.filled(32, '11').join(),
  preimageHex: value,
);

String _repeat(String value, int count) => List.filled(count, value).join();
