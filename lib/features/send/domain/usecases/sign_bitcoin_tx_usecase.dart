import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';

class SignBitcoinTxUsecase {
  final BitcoinSigningPort _bitcoinSigningPort;

  SignBitcoinTxUsecase(this._bitcoinSigningPort);

  Future<({String psbt, bool isFinalized})> finalize(String psbt) =>
      _bitcoinSigningPort.finalizePsbt(psbt);

  Future<({String signedPsbt, int txSize, bool isFinalized})> execute({
    required String psbt,
    required String walletId,
    String? externalPsbt,
    bool requireFinalized = true,
    bool tryFinalize = true,
    String? signerId,
  }) async {
    try {
      final signingResult = externalPsbt == null
          ? await _bitcoinSigningPort.signPsbt(
              psbt,
              walletId: walletId,
              tryFinalize: tryFinalize,
              signerId: signerId,
            )
          : await _bitcoinSigningPort.combinePsbts(
              currentPsbt: psbt,
              signedPsbt: externalPsbt,
              walletId: walletId,
              tryFinalize: tryFinalize,
            );
      if (requireFinalized && !signingResult.isFinalized) {
        throw StateError('Bitcoin transaction is not fully signed');
      }
      final size = await _bitcoinSigningPort.getTxSize(
        psbt: signingResult.psbt,
        walletId: walletId,
      );
      return (
        signedPsbt: signingResult.psbt,
        txSize: size,
        isFinalized: signingResult.isFinalized,
      );
    } catch (e) {
      throw SignBitcoinTxException(e.toString());
    }
  }
}

class SignBitcoinTxException extends BullException {
  SignBitcoinTxException(super.message);
}
