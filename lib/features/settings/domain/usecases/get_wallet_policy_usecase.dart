import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_signing_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bb_mobile/features/settings/domain/settings_failure.dart';
import 'package:meta/meta.dart';

class GetWalletPolicyUsecase {
  final BitcoinSigningPort _bitcoinSigningPort;

  const GetWalletPolicyUsecase({required this._bitcoinSigningPort});

  @useResult
  Future<Result<BitcoinWalletPolicy, SettingsFailure>> execute(
    String walletId,
  ) async {
    try {
      final policy = await _bitcoinSigningPort.getPolicy(walletId: walletId);
      return Ok(policy);
    } on Exception catch (error, stackTrace) {
      log.severe(
        message: 'Failed to load wallet spending conditions',
        error: error.runtimeType,
        trace: stackTrace,
      );
      return const Err(SettingsWalletPolicyFailure());
    }
  }
}
