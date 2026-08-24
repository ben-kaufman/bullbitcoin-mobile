import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/ledger/domain/entities/ledger_device_entity.dart';
import 'package:bb_mobile/core/ledger/domain/repositories/ledger_device_repository.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/descriptor_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_descriptor_key.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/watch_only_wallet_entity.dart';

class GetLedgerWatchOnlyWalletUsecase {
  final LedgerDeviceRepository _repository;
  final SettingsRepository _settingsRepository;

  GetLedgerWatchOnlyWalletUsecase({
    required this._repository,
    required this._settingsRepository,
  });

  Future<WatchOnlyWalletEntity> execute({
    required String label,
    required LedgerDeviceEntity device,
    ScriptType scriptType = ScriptType.bip84,
    int account = 0,
  }) async {
    final settings = await _settingsRepository.fetch();
    final network = Network.fromEnvironment(
      isTestnet: settings.environment.isTestnet,
      isLiquid: false,
    );

    final derivationPath =
        "m/${scriptType.purpose}'/${network.coinType}'/$account'";

    final masterFingerprint = await _repository.getMasterFingerprint(device);
    final xpub = await _repository.getXpub(
      device,
      derivationPath: derivationPath,
      scriptType: scriptType,
    );

    final descriptor =
        DescriptorDerivation.derivePublicBitcoinMultipathDescriptorFromXpub(
          xpub,
          scriptType: scriptType,
          isTestnet: network.isTestnet,
          masterFingerprint: masterFingerprint,
          derivationPath: derivationPath,
        );

    return WatchOnlyWalletEntity.descriptor(
      descriptor: descriptor,
      network: network,
      scriptType: scriptType,
      signers: [
        WalletSigner(
          id: 'signer-0',
          signer: SignerEntity.remote,
          signerDevice: device.deviceType,
          descriptorKeys: [
            WalletDescriptorKey(
              id: 'key-0',
              signerId: 'signer-0',
              masterFingerprint: masterFingerprint,
              xpubFingerprint: Bip32Derivation.getBip32Xpub(
                xpub,
              ).fingerprintHex,
              xpub: xpub,
              derivationPath: derivationPath,
            ),
          ],
        ),
      ],
      label: label,
    );
  }
}
