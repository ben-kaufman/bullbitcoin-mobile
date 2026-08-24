import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/send/public/send_facade.dart';
import 'package:bb_mobile/features/wallet/domain/wallet_pending_transactions_failure.dart';

class WatchWalletPendingTransactionsUsecase {
  final SendFacade _sendFacade;

  const WatchWalletPendingTransactionsUsecase(this._sendFacade);

  Stream<
    Result<PendingBitcoinTransactionSnapshot, WalletPendingTransactionsFailure>
  >
  execute(String walletId) => _sendFacade
      .watchPending(walletId)
      .map(
        (result) => result.mapErr(
          (failure) => WalletPendingTransactionsLoadFailure(
            failure.runtimeType.toString(),
          ),
        ),
      );
}
