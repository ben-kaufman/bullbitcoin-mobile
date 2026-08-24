import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_descriptor_key.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Wallet wallet({
    String derivationPath = "m/84'/0'/0'",
    String externalDescriptor = 'wpkh(xpub/0/*)',
    String internalDescriptor = 'wpkh(xpub/1/*)',
    ScriptType? scriptType = ScriptType.bip84,
    SignerEntity signer = SignerEntity.local,
    SignerDeviceEntity? signerDevice,
    int descriptorKeyCount = 1,
  }) {
    final expectedInternalDescriptor = externalDescriptor.replaceAll(
      '/0/*',
      '/1/*',
    );
    final publicDescriptor = internalDescriptor == expectedInternalDescriptor
        ? externalDescriptor.replaceAll('/0/*', '/<0;1>/*')
        : externalDescriptor;

    return Wallet(
      origin: 'wallet',
      network: Network.bitcoinMainnet,
      signers: [
        WalletSigner(
          id: 'signer-0',
          signer: signer,
          signerDevice: signerDevice,
          descriptorKeys: [
            for (var index = 0; index < descriptorKeyCount; index++)
              WalletDescriptorKey(
                id: 'key-$index',
                signerId: 'signer-0',
                masterFingerprint: '00000000',
                xpubFingerprint: '00000000',
                xpub: 'xpub-$index',
                derivationPath: derivationPath,
              ),
          ],
        ),
      ],
      scriptType: scriptType,
      publicDescriptor: publicDescriptor,
      balanceSat: BigInt.zero,
    );
  }

  group('Wallet.isStandardLocalSingleSignatureWallet', () {
    test('accepts standard apostrophe and h hardened paths', () {
      expect(wallet().isStandardLocalSingleSignatureWallet, isTrue);
      expect(
        wallet(
          derivationPath: 'm/84h/0h/0h',
        ).isStandardLocalSingleSignatureWallet,
        isTrue,
      );
    });

    test('rejects a nonstandard descriptor keychain', () {
      expect(
        wallet(
          externalDescriptor: 'wpkh(xpub/2/*)',
          internalDescriptor: 'wpkh(xpub/3/*)',
        ).isStandardLocalSingleSignatureWallet,
        isFalse,
      );
    });

    test('rejects an arbitrary descriptor policy', () {
      expect(
        wallet(
          scriptType: null,
          externalDescriptor: 'wsh(pk(xpub/0/*))',
          internalDescriptor: 'wsh(pk(xpub/1/*))',
        ).isStandardLocalSingleSignatureWallet,
        isFalse,
      );
    });

    test('rejects a remote signer', () {
      expect(
        wallet(
          signer: SignerEntity.remote,
        ).isStandardLocalSingleSignatureWallet,
        isFalse,
      );
    });
  });

  test('keeps each Coldcard signing transport available', () {
    final mk4 = wallet(
      signer: SignerEntity.remote,
      signerDevice: SignerDeviceEntity.coldcardMk4,
    );
    final q = wallet(
      signer: SignerEntity.remote,
      signerDevice: SignerDeviceEntity.coldcardQ,
    );
    final taprootMk4 = wallet(
      externalDescriptor: 'tr(xpub/0/*)',
      internalDescriptor: 'tr(xpub/1/*)',
      scriptType: null,
      signer: SignerEntity.remote,
      signerDevice: SignerDeviceEntity.coldcardMk4,
    );

    expect(mk4.supportsQrSigningFor(mk4.signers.single), isFalse);
    expect(mk4.supportsDevicePsbtFlowFor(mk4.signers.single), isTrue);
    expect(q.supportsQrSigningFor(q.signers.single), isTrue);
    expect(q.supportsDevicePsbtFlowFor(q.signers.single), isTrue);
    expect(
      taprootMk4.supportsDevicePsbtFlowFor(taprootMk4.signers.single),
      isTrue,
    );
  });

  test('offers BitBox policies for only one controlled account key', () {
    final singleAccount = wallet(
      externalDescriptor: 'wsh(pk(xpub/0/*))',
      internalDescriptor: 'wsh(pk(xpub/1/*))',
      scriptType: null,
      signer: SignerEntity.remote,
      signerDevice: SignerDeviceEntity.bitbox02,
    );
    final multipleAccounts = wallet(
      externalDescriptor: 'wsh(or_d(pk(xpub-a/0/*),pk(xpub-b/0/*)))',
      internalDescriptor: 'wsh(or_d(pk(xpub-a/1/*),pk(xpub-b/1/*)))',
      scriptType: null,
      signer: SignerEntity.remote,
      signerDevice: SignerDeviceEntity.bitbox02,
      descriptorKeyCount: 2,
    );
    final hashlock = wallet(
      externalDescriptor:
          'wsh(and_v(v:pk(xpub/0/*),sha256(0000000000000000000000000000000000000000000000000000000000000000)))',
      internalDescriptor:
          'wsh(and_v(v:pk(xpub/1/*),sha256(0000000000000000000000000000000000000000000000000000000000000000)))',
      scriptType: null,
      signer: SignerEntity.remote,
      signerDevice: SignerDeviceEntity.bitbox02,
    );

    expect(
      singleAccount.supportsWalletPolicySigner(singleAccount.signers.single),
      isTrue,
    );
    expect(
      multipleAccounts.supportsWalletPolicySigner(
        multipleAccounts.signers.single,
      ),
      isFalse,
    );
    expect(
      hashlock.supportsWalletPolicySigner(hashlock.signers.single),
      isFalse,
    );
  });
}
