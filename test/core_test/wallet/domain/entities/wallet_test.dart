import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Wallet wallet({
    String derivationPath = "m/84'/0'/0'",
    String externalDescriptor = 'wpkh(xpub/0/*)',
    String internalDescriptor = 'wpkh(xpub/1/*)',
    ScriptType? scriptType = ScriptType.bip84,
    SignerEntity signer = SignerEntity.local,
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
        WalletSigner.single(
          masterFingerprint: '00000000',
          xpubFingerprint: '00000000',
          xpub: 'xpub',
          derivationPath: derivationPath,
          signer: signer,
          signerDevice: null,
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
}
