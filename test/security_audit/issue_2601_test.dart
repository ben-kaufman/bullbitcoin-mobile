import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Security audit reproducer for https://github.com/SatoshiPortal/bullbitcoin-mobile/issues/2601
// Finding: an ambiguous broadcast failure returns to confirmation and permits a fresh build/sign retry.
// Regression test for the fix.
void main() {
  group('Security audit #2601 ambiguous broadcast retry', () {
    test(
      'broadcast failure clears no retry barrier and confirmation rebuilds',
      () {
        final source = File(
          'lib/features/send/presentation/bloc/send_cubit.dart',
        ).readAsStringSync();
        final retry = source.substring(
          source.indexOf('Future<void> onConfirmTransactionClicked()'),
          source.indexOf('Future<void> currencyCodeChanged'),
        );
        expect(retry, contains('!state.hasFinalizedBitcoinTransaction'));
        expect(retry, contains('await createTransaction()'));
        expect(
          File(
            'lib/features/send/presentation/bloc/send_state.dart',
          ).readAsStringSync(),
          contains('signedBitcoinPsbt != null || signedBitcoinTx != null'),
        );
        expect(source, contains("'BroadcastTransactionException'"));
        expect(source, contains('isBroadcastFailure: true'));
        expect(source, contains('step: SendStep.confirm'));
      },
    );
  });
}
