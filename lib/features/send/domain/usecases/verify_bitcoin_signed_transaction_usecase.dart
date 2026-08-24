import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';

class VerifyBitcoinSignedTransactionUsecase {
  final BitcoinSigningPort _bitcoinSigningPort;

  VerifyBitcoinSignedTransactionUsecase(this._bitcoinSigningPort);

  Future<({String transaction, int txSize})> execute({
    required String psbt,
    required String transaction,
  }) => _bitcoinSigningPort.verifyFinalTransaction(
    psbt: psbt,
    transaction: transaction,
  );
}
