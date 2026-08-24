import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/seed/domain/seed_lookup_port.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_descriptor_port.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_descriptor_key.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/domain/import_watch_only_failure.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/parse_watch_only_input_usecase.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/watch_only_wallet_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBitcoinDescriptorPort extends Mock
    implements BitcoinDescriptorPort {}

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockSeedLookupPort extends Mock implements SeedLookupPort {}

class _MockSettings extends Mock implements SettingsEntity {}

const _xpub =
    'xpub6DJwRncrB8eNrzUq8XxgjwCZsEeWP8FeqBJbJQZ8JfuDwLdAzyjhHiHJieNuar1wjQTyihhMWtaKGE4DUd8uBgtyrNJqF5drwbNVUqb83b7';

void main() {
  late _MockBitcoinDescriptorPort descriptorPort;
  late _MockGetSettingsUsecase getSettingsUsecase;
  late _MockSeedLookupPort seedLookup;
  late ParseWatchOnlyInputUsecase usecase;

  setUp(() {
    descriptorPort = _MockBitcoinDescriptorPort();
    getSettingsUsecase = _MockGetSettingsUsecase();
    seedLookup = _MockSeedLookupPort();
    final settings = _MockSettings();
    when(() => settings.environment).thenReturn(Environment.mainnet);
    when(() => getSettingsUsecase.execute()).thenAnswer((_) async => settings);
    usecase = ParseWatchOnlyInputUsecase(
      descriptorPort,
      getSettingsUsecase,
      seedLookup,
    );
  });

  group('ParseWatchOnlyInputUsecase', () {
    test('maps raw xpub input to Bull wallet types', () async {
      final result = await usecase.execute(_xpub);

      expect(result, isA<Ok<WatchOnlyWalletEntity, ImportWatchOnlyFailure>>());
      final entity =
          (result as Ok<WatchOnlyWalletEntity, ImportWatchOnlyFailure>).value
              as WatchOnlyXpubEntity;
      expect(entity.extendedPublicKey, _xpub);
      expect(entity.canonicalXpub, _xpub);
      expect(entity.network, Network.bitcoinMainnet);
      expect(entity.scriptType, ScriptType.bip44);
      verifyNever(() => getSettingsUsecase.execute());
    });

    test('preserves xpub origin and supplied signer device', () async {
      final result = await usecase.execute(
        "[deadbeef/44'/0'/0']$_xpub",
        signerDevice: SignerDeviceEntity.krux,
      );

      final entity =
          (result as Ok<WatchOnlyWalletEntity, ImportWatchOnlyFailure>).value
              as WatchOnlyXpubEntity;
      expect(entity.canonicalXpub, _xpub);
      expect(entity.scriptType, ScriptType.bip44);
      expect(entity.masterFingerprint, 'deadbeef');
      expect(entity.derivationPath, "m/44'/0'/0'");
      expect(entity.signer, SignerEntity.remote);
      expect(entity.signerDevice, SignerDeviceEntity.krux);
    });

    test('recognizes a Bull key only when its account xpub matches', () async {
      const input = 'wpkh(xpub/0/*)';
      const canonical = 'wpkh(xpub/<0;1>/*)#checksum';
      const localFingerprint = '86241f88';
      const remoteFingerprint = '12345678';
      final seedBytes = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );
      final localXpub = (await Bip32Derivation.getAccountXpub(
        seedBytes: seedBytes,
        scriptType: ScriptType.bip84,
        network: Network.bitcoinMainnet,
      )).toBase58();
      when(
        () => descriptorPort.parseBitcoinDescriptor(
          descriptor: input,
          network: Network.bitcoinMainnet,
        ),
      ).thenReturn((
        descriptor: canonical,
        inferredChangePath: false,
        scriptType: ScriptType.bip84,
        descriptorKeys: [
          _descriptorKey(
            masterFingerprint: localFingerprint,
            xpubFingerprint: '11111111',
            xpub: localXpub,
            derivationPath: 'm/84h/0h/0h',
            signer: SignerEntity.none,
            signerDevice: null,
          ),
          _descriptorKey(
            masterFingerprint: remoteFingerprint,
            xpubFingerprint: '22222222',
            xpub: 'xpub-remote',
            signer: SignerEntity.none,
            signerDevice: null,
          ),
        ],
      ));
      when(
        () => seedLookup.exists(localFingerprint),
      ).thenAnswer((_) async => true);
      when(() => seedLookup.get(localFingerprint)).thenAnswer(
        (_) async =>
            Seed.bytes(bytes: seedBytes, masterFingerprint: localFingerprint),
      );
      when(
        () => seedLookup.exists(remoteFingerprint),
      ).thenAnswer((_) async => false);

      final result = await usecase.execute(
        input,
        signerDevice: SignerDeviceEntity.coldcardQ,
      );

      final entity =
          (result as Ok<WatchOnlyWalletEntity, ImportWatchOnlyFailure>).value
              as WatchOnlyDescriptorEntity;
      expect(entity.inferredChangePath, isFalse);
      expect(entity.descriptor, canonical);
      expect(entity.scriptType, ScriptType.bip84);
      expect(entity.signers, hasLength(2));
      expect(entity.signers.first.signer, SignerEntity.local);
      expect(entity.signers.first.signerDevice, isNull);
      expect(entity.signers.last.signer, SignerEntity.remote);
      expect(entity.signers.last.signerDevice, SignerDeviceEntity.coldcardQ);
    });

    test('does not trust a matching fingerprint with another xpub', () async {
      const input = 'wpkh(xpub/0/*)';
      const fingerprint = '86241f88';
      final seedBytes = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );
      when(
        () => descriptorPort.parseBitcoinDescriptor(
          descriptor: input,
          network: Network.bitcoinMainnet,
        ),
      ).thenReturn((
        descriptor: 'wpkh(xpub/<0;1>/*)#checksum',
        inferredChangePath: true,
        scriptType: ScriptType.bip84,
        descriptorKeys: [
          _descriptorKey(
            masterFingerprint: fingerprint,
            xpubFingerprint: '11111111',
            xpub: _xpub,
            derivationPath: 'm/84h/0h/0h',
            signer: SignerEntity.none,
            signerDevice: null,
          ),
        ],
      ));
      when(() => seedLookup.exists(fingerprint)).thenAnswer((_) async => true);
      when(() => seedLookup.get(fingerprint)).thenAnswer(
        (_) async =>
            Seed.bytes(bytes: seedBytes, masterFingerprint: fingerprint),
      );

      final result = await usecase.execute(input);

      final entity =
          (result as Ok<WatchOnlyWalletEntity, ImportWatchOnlyFailure>).value
              as WatchOnlyDescriptorEntity;
      expect(entity.inferredChangePath, isTrue);
      expect(entity.signers.single.signer, SignerEntity.remote);
    });

    test('applies a scanned device to a single external signer', () async {
      const input = 'wpkh(xpub/0/*)';
      const canonical = 'wpkh(xpub/<0;1>/*)#checksum';
      const fingerprint = '12345678';
      when(
        () => descriptorPort.parseBitcoinDescriptor(
          descriptor: input,
          network: Network.bitcoinMainnet,
        ),
      ).thenReturn((
        descriptor: canonical,
        inferredChangePath: false,
        scriptType: ScriptType.bip84,
        descriptorKeys: [
          _descriptorKey(
            masterFingerprint: fingerprint,
            xpubFingerprint: '22222222',
            xpub: 'xpub-remote',
            signer: SignerEntity.none,
            signerDevice: null,
          ),
        ],
      ));
      when(() => seedLookup.exists(fingerprint)).thenAnswer((_) async => false);

      final result = await usecase.execute(
        input,
        signerDevice: SignerDeviceEntity.coldcardQ,
      );

      final entity =
          (result as Ok<WatchOnlyWalletEntity, ImportWatchOnlyFailure>).value
              as WatchOnlyDescriptorEntity;
      expect(entity.signers.single.signer, SignerEntity.remote);
      expect(entity.signers.single.signerDevice, SignerDeviceEntity.coldcardQ);
    });

    test('applies one scanned device to every key for the signer', () async {
      const input = 'wsh(or_d(pk(key-a),pk(key-b)))';
      const fingerprint = '12345678';
      when(
        () => descriptorPort.parseBitcoinDescriptor(
          descriptor: input,
          network: Network.bitcoinMainnet,
        ),
      ).thenReturn((
        descriptor: '$input#checksum',
        inferredChangePath: false,
        scriptType: null,
        descriptorKeys: [
          _descriptorKey(
            masterFingerprint: fingerprint,
            xpubFingerprint: '11111111',
            xpub: 'xpub-first',
            signer: SignerEntity.none,
            signerDevice: null,
          ),
          _descriptorKey(
            masterFingerprint: fingerprint,
            xpubFingerprint: '22222222',
            xpub: 'xpub-second',
            signer: SignerEntity.none,
            signerDevice: null,
          ),
        ],
      ));
      when(() => seedLookup.exists(fingerprint)).thenAnswer((_) async => false);

      final result = await usecase.execute(
        input,
        signerDevice: SignerDeviceEntity.coldcardQ,
      );

      final entity =
          (result as Ok<WatchOnlyWalletEntity, ImportWatchOnlyFailure>).value
              as WatchOnlyDescriptorEntity;
      expect(entity.signers, hasLength(1));
      expect(
        entity.signers.map((signer) => signer.signerDevice),
        everyElement(SignerDeviceEntity.coldcardQ),
      );
    });

    test('maps unparseable input to InvalidFormatFailure', () async {
      const input =
          'this is definitely not a descriptor or an extended public key';
      when(
        () => descriptorPort.parseBitcoinDescriptor(
          descriptor: input,
          network: Network.bitcoinMainnet,
        ),
      ).thenThrow(const FormatException('invalid descriptor'));

      final result = await usecase.execute(input);

      expect(result, isA<Err<WatchOnlyWalletEntity, ImportWatchOnlyFailure>>());
      final failure =
          (result as Err<WatchOnlyWalletEntity, ImportWatchOnlyFailure>)
              .failure;
      expect(failure, isA<InvalidFormatFailure>());
      expect(failure.logMessage, isNull);
    });

    test('maps Taproot input to TaprootUnsupportedFailure', () async {
      const input = 'tr(xpub/<0;1>/*)';
      when(
        () => descriptorPort.parseBitcoinDescriptor(
          descriptor: input,
          network: Network.bitcoinMainnet,
        ),
      ).thenThrow(const UnsupportedTaprootDescriptorException());

      final result = await usecase.execute(input);

      expect(result, isA<Err<WatchOnlyWalletEntity, ImportWatchOnlyFailure>>());
      final failure =
          (result as Err<WatchOnlyWalletEntity, ImportWatchOnlyFailure>)
              .failure;
      expect(failure, isA<TaprootUnsupportedFailure>());
      expect(failure.logMessage, isNull);
    });

    test('maps fixed public keys to their unsupported failure', () async {
      const fixedPublicKey =
          '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';
      const input = 'wsh(sortedmulti(2,$_xpub/<0;1>/*,$fixedPublicKey))';
      when(
        () => descriptorPort.parseBitcoinDescriptor(
          descriptor: input,
          network: Network.bitcoinMainnet,
        ),
      ).thenThrow(const UnsupportedFixedPublicKeyDescriptorException());

      final result = await usecase.execute(input);

      expect(result, isA<Err<WatchOnlyWalletEntity, ImportWatchOnlyFailure>>());
      final failure =
          (result as Err<WatchOnlyWalletEntity, ImportWatchOnlyFailure>)
              .failure;
      expect(failure, isA<FixedPublicKeyUnsupportedFailure>());
      expect(failure.logMessage, isNull);
    });
  });
}

WalletDescriptorKey _descriptorKey({
  required String masterFingerprint,
  required String xpubFingerprint,
  required String xpub,
  String? derivationPath,
  required SignerEntity signer,
  required SignerDeviceEntity? signerDevice,
}) => WalletDescriptorKey(
  id: 'key-$xpubFingerprint',
  signerId: 'unassigned-$xpubFingerprint',
  masterFingerprint: masterFingerprint,
  xpubFingerprint: xpubFingerprint,
  xpub: xpub,
  derivationPath: derivationPath,
);
