import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';

class ApplyBitcoinPolicyPreimagesUsecase {
  final BitcoinSigningPort _bitcoinSigningPort;

  ApplyBitcoinPolicyPreimagesUsecase(this._bitcoinSigningPort);

  Future<String> execute({
    required String psbt,
    required Iterable<BitcoinPolicyPreimage> preimages,
  }) => _bitcoinSigningPort.applyPolicyPreimages(
    psbt: psbt,
    preimages: preimages.toList(growable: false),
  );
}
