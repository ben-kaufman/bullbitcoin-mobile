import 'package:bb_mobile/core/failures/failure.dart';

sealed class WalletPendingTransactionsFailure extends Failure {
  const WalletPendingTransactionsFailure([super.logMessage]);
}

final class WalletPendingTransactionsLoadFailure
    extends WalletPendingTransactionsFailure {
  const WalletPendingTransactionsLoadFailure([super.logMessage]);
}

final class WalletPendingTransactionDeleteFailure
    extends WalletPendingTransactionsFailure {
  const WalletPendingTransactionDeleteFailure([super.logMessage]);
}
