import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';

class ValidateBitcoinPolicyPreimageUsecase {
  final BitcoinSigningPort _bitcoinSigningPort;

  ValidateBitcoinPolicyPreimageUsecase(this._bitcoinSigningPort);

  Future<BitcoinPolicyPreimage?> execute({
    required BitcoinHashlockPolicyNode hashlock,
    required String preimageHex,
  }) async {
    try {
      final preimage = BitcoinPolicyPreimage(
        type: hashlock.type,
        hash: hashlock.hash,
        preimageHex: preimageHex.trim(),
      );
      return await _bitcoinSigningPort.validatePolicyPreimage(preimage)
          ? preimage
          : null;
    } on ArgumentError {
      return null;
    }
  }
}
