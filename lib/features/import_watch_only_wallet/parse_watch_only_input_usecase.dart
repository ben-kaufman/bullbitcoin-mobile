import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/domain/seed_lookup_port.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_descriptor_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_descriptor_key.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/domain/import_watch_only_failure.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/watch_only_wallet_entity.dart';
import 'package:meta/meta.dart';
import 'package:satoshifier/satoshifier.dart' as satoshifier;

/// Parses pasted/scanned text into a [WatchOnlyWalletEntity].
///
/// Extended public keys are parsed through Satoshifier and descriptors through
/// the descriptor port. Parser failures are mapped to a sanitized
/// [InvalidFormatFailure] without logging the pasted input or parser message.
class ParseWatchOnlyInputUsecase {
  final BitcoinDescriptorPort _descriptorPort;
  final GetSettingsUsecase _getSettingsUsecase;
  final SeedLookupPort _seedLookup;

  ParseWatchOnlyInputUsecase(
    this._descriptorPort,
    this._getSettingsUsecase,
    this._seedLookup,
  );

  @useResult
  Future<Result<WatchOnlyWalletEntity, ImportWatchOnlyFailure>> execute(
    String input, {
    SignerDeviceEntity? signerDevice,
  }) async {
    try {
      final normalizedInput = input.trim();
      final originMatch = RegExp(
        r'^\[([0-9a-fA-F]{8})(/[^\]]+)?\]',
      ).firstMatch(normalizedInput);
      final xpubInput = normalizedInput.replaceFirst(
        RegExp(r'^\[[^\]]+\]'),
        '',
      );
      final parsedXpub = await satoshifier.WatchOnlyXpubParser.tryParse(
        xpubInput,
      );
      if (parsedXpub case satoshifier.WatchOnlyXpub(:final extendedPubkey)) {
        return Ok(
          WatchOnlyWalletEntity.xpub(
            extendedPublicKey: extendedPubkey.pubBase58,
            canonicalXpub: extendedPubkey.xpub,
            network: Network.fromName(extendedPubkey.network.name),
            scriptType: ScriptType.fromName(extendedPubkey.derivation.name),
            masterFingerprint: originMatch?.group(1)?.toLowerCase(),
            derivationPath: switch (originMatch?.group(2)) {
              final path? => 'm$path',
              null => null,
            },
            signer: signerDevice == null
                ? SignerEntity.none
                : SignerEntity.remote,
            signerDevice: signerDevice,
          ),
        );
      }

      final settings = await _getSettingsUsecase.execute();
      final network = Network.fromEnvironment(
        isTestnet: settings.environment.isTestnet,
        isLiquid: false,
      );
      final parsedDescriptor = _descriptorPort.parseBitcoinDescriptor(
        descriptor: normalizedInput,
        network: network,
      );
      final keyGroups = <String, List<WalletDescriptorKey>>{};
      for (final key in parsedDescriptor.descriptorKeys) {
        final groupingHint = key.masterFingerprint.isEmpty
            ? 'key:${key.id}'
            : 'master:${key.masterFingerprint.toLowerCase()}';
        keyGroups.putIfAbsent(groupingHint, () => []).add(key);
      }
      final localGroups = <String>{};
      for (final entry in keyGroups.entries) {
        if (await _isLocalSigner(entry.value)) localGroups.add(entry.key);
      }
      final externalSignerCount = keyGroups.length - localGroups.length;
      final signers = [
        for (final (index, entry) in keyGroups.entries.indexed)
          WalletSigner(
            id: 'signer-$index',
            signer: localGroups.contains(entry.key)
                ? SignerEntity.local
                : SignerEntity.remote,
            signerDevice:
                !localGroups.contains(entry.key) && externalSignerCount == 1
                ? signerDevice
                : null,
            descriptorKeys: [
              for (final key in entry.value)
                key.copyWith(signerId: 'signer-$index'),
            ],
          ),
      ];
      return Ok(
        WatchOnlyWalletEntity.descriptor(
          descriptor: parsedDescriptor.descriptor,
          network: network,
          scriptType: parsedDescriptor.scriptType,
          signers: signers,
          inferredChangePath: parsedDescriptor.inferredChangePath,
        ),
      );
    } on UnsupportedFixedPublicKeyDescriptorException catch (_, st) {
      log.warning(
        'Fixed public key descriptor import is not supported',
        trace: st,
      );
      return const Err(FixedPublicKeyUnsupportedFailure());
    } on Exception catch (_, st) {
      // Parser errors may contain pasted key material. Preserve the trace but
      // never forward the raw rejection to logs or user-facing state.
      log.warning('Failed to parse watch-only input', trace: st);
      return const Err(InvalidFormatFailure());
    }
  }

  Future<bool> _isLocalSigner(List<WalletDescriptorKey> keys) async {
    final fingerprint = keys.first.masterFingerprint;
    if (fingerprint.isEmpty || !await _seedLookup.exists(fingerprint)) {
      return false;
    }

    final seed = await _seedLookup.get(fingerprint);
    return keys.every((key) {
      final derivationPath = key.derivationPath;
      return derivationPath != null &&
          Bip32Derivation.seedMatchesXpub(
            seedBytes: seed.bytes,
            derivationPath: derivationPath,
            xpub: key.xpub,
          );
    });
  }
}
