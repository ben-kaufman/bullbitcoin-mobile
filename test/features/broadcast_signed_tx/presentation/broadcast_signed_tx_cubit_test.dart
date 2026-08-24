import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_bitcoin_transaction_usecase.dart';
import 'package:bb_mobile/features/broadcast_signed_tx/domain/parse_signer_result_usecase.dart';
import 'package:bb_mobile/features/broadcast_signed_tx/presentation/broadcast_signed_tx_cubit.dart';
import 'package:bb_mobile/features/broadcast_signed_tx/type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBroadcastBitcoinTransactionUsecase extends Mock
    implements BroadcastBitcoinTransactionUsecase {}

class _MockParseSignerResultUsecase extends Mock
    implements ParseSignerResultUsecase {}

void main() {
  late _MockBroadcastBitcoinTransactionUsecase broadcastUsecase;
  late _MockParseSignerResultUsecase parseSignerResultUsecase;

  setUp(() {
    broadcastUsecase = _MockBroadcastBitcoinTransactionUsecase();
    parseSignerResultUsecase = _MockParseSignerResultUsecase();
  });

  BroadcastSignedTxCubit buildCubit() => BroadcastSignedTxCubit(
    broadcastBitcoinTransactionUsecase: broadcastUsecase,
    parseSignerResultUsecase: parseSignerResultUsecase,
    request: const BroadcastSignedTxRequest(collectSignerResult: true),
  );

  group('signer result collection', () {
    test('stores the parsed signer result', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      when(
        () => parseSignerResultUsecase.execute('signer-result'),
      ).thenReturn('normalized-result');

      await cubit.tryParseTransaction('signer-result');

      expect(cubit.state.collectedSignerResult, 'normalized-result');
      expect(cubit.state.failure, isNull);
      verify(() => parseSignerResultUsecase.execute('signer-result')).called(1);
    });

    test('holds a failure when the signer result cannot be parsed', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      when(
        () => parseSignerResultUsecase.execute('invalid'),
      ).thenThrow(const FormatException('invalid signer result'));

      await cubit.tryParseTransaction('invalid');

      expect(cubit.state.collectedSignerResult, isNull);
      expect(cubit.state.failure, isNotNull);
    });
  });
}
