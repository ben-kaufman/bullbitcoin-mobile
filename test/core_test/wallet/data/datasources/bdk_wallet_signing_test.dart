import 'package:bb_mobile/core/utils/descriptor_derivation.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_facade.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/mappers/bitcoin_wallet_policy_mapper.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_model.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_psbt_review_exception.dart';
import 'package:bb_mobile/core/wallet/domain/entities/bitcoin_policy.dart';
import 'package:bitcoin_base/bitcoin_base.dart' as bitcoin_base;
import 'package:bull_sdk/bdk.dart' as bdk;
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../bdk_wallet_test_fixture.dart';

void main() {
  late List<SignerDescriptorKeys> signers;
  late String externalPublicDescriptor;
  late String internalPublicDescriptor;
  late BdkWalletDatasource datasource;

  setUpAll(() {
    signers = testMnemonics.map(deriveSignerKeys).toList();
    externalPublicDescriptor =
        DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
          threshold: 2,
          descriptorKeys: signers
              .map((signer) => signer.externalPublic)
              .toList(),
        );
    internalPublicDescriptor =
        DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
          threshold: 2,
          descriptorKeys: signers
              .map((signer) => signer.internalPublic)
              .toList(),
        );
  });

  setUp(() {
    datasource = BdkWalletDatasource();
  });

  group('BdkWalletDatasource multisig PSBT operations', () {
    test('verifies inputs, recipients, and change against descriptors', () {
      final recipientDescriptors = singleSignatureDescriptors(
        testMnemonics.last,
      );
      final recipientWallet = BdkFacade.createEphemeralDescriptorWallet(
        descriptor: twoPathDescriptor(
          recipientDescriptors.external,
          recipientDescriptors.internal,
        ),
        isTestnet: true,
      );
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
        recipientScript: recipientWallet
            .peekAddress(keychain: bdk.KeychainKind.external_, index: 5)
            .address
            .scriptPubkey(),
      );
      final wallet =
          WalletModel.publicBdk(
                id: 'review',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;

      final review = datasource.inspectPsbt(
        unsignedPsbt,
        wallet: wallet,
        walletFingerprints: signers.map((signer) => signer.fingerprint).toSet(),
      );

      expect(review.inputs, hasLength(1));
      expect(review.feeSat, BigInt.from(1000));
      expect(
        review.outputs.where((output) => output.isWalletOwned),
        hasLength(1),
      );
      expect(
        review.outputs.where((output) => !output.isWalletOwned),
        hasLength(1),
      );
      expect(
        review.estimatedTransactionVsize,
        greaterThan(bdk.Psbt(psbtBase64: unsignedPsbt).extractTx().vsize()),
      );
    });

    test('estimates completed size and uses exact size after finalization', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final wallet =
          WalletModel.publicBdk(
                id: 'size',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;
      final estimated = datasource.decodeTxSize(unsignedPsbt, wallet: wallet);
      final first = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      expect(datasource.decodeTxSize(first.psbt, wallet: wallet), estimated);
      final second = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 1,
      );
      final finalized = datasource.finalizePsbt(
        datasource.combinePsbts(first: first.psbt, second: second.psbt),
      );
      final exact = bdk.Psbt(psbtBase64: finalized.psbt).extractTx().vsize();

      expect(finalized.isFinalized, isTrue);
      expect(datasource.decodeTxSize(finalized.psbt, wallet: wallet), exact);
      expect(estimated, greaterThanOrEqualTo(exact));
    });

    test('reviews a finalized PSBT after signing metadata is cleared', () {
      final recipientDescriptors = singleSignatureDescriptors(
        testMnemonics.last,
      );
      final recipientWallet = BdkFacade.createEphemeralDescriptorWallet(
        descriptor: twoPathDescriptor(
          recipientDescriptors.external,
          recipientDescriptors.internal,
        ),
        isTestnet: true,
      );
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
        recipientScript: recipientWallet
            .peekAddress(keychain: bdk.KeychainKind.external_, index: 5)
            .address
            .scriptPubkey(),
      );
      final wallet =
          WalletModel.publicBdk(
                id: 'finalized-review',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;
      final first = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final second = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 1,
      );
      final finalized = datasource.finalizePsbt(
        datasource.combinePsbts(first: first.psbt, second: second.psbt),
      );

      final review = datasource.inspectPsbt(
        finalized.psbt,
        wallet: wallet,
        walletFingerprints: signers.map((signer) => signer.fingerprint).toSet(),
      );

      expect(finalized.isFinalized, isTrue);
      expect(review.inputs, hasLength(1));
      expect(
        review.outputs.where((output) => output.isWalletOwned),
        hasLength(1),
      );
      expect(
        review.outputs.where((output) => !output.isWalletOwned),
        hasLength(1),
      );
    });

    test('estimates a regular single-signature Bitcoin send', () {
      final descriptors = singleSignatureDescriptors(testMnemonics.first);
      final wallet =
          WalletModel.publicBdk(
                id: 'regular-send-size',
                descriptor: twoPathDescriptor(
                  descriptors.external,
                  descriptors.internal,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          descriptors.external,
          descriptors.internal,
        ),
      );
      final estimated = datasource.decodeTxSize(unsignedPsbt, wallet: wallet);
      final root = bdk.DescriptorSecretKey(
        networkKind: bdk.NetworkKind.test,
        mnemonic: bdk.Mnemonic.fromString(mnemonic: testMnemonics.first),
        password: null,
      );
      final signed = datasource.signPsbtWithDescriptor(
        unsignedPsbt,
        descriptor: twoPathDescriptor(
          bdk.Descriptor.newBip84(
            secretKey: root,
            keychainKind: bdk.KeychainKind.external_,
            networkKind: bdk.NetworkKind.test,
          ).toStringWithSecret(),
          bdk.Descriptor.newBip84(
            secretKey: root,
            keychainKind: bdk.KeychainKind.internal,
            networkKind: bdk.NetworkKind.test,
          ).toStringWithSecret(),
        ),
        isTestnet: true,
      );
      final exact = bdk.Psbt(psbtBase64: signed.psbt).extractTx().vsize();

      expect(signed.isFinalized, isTrue);
      expect(datasource.decodeTxSize(signed.psbt, wallet: wallet), exact);
      expect(estimated, greaterThanOrEqualTo(exact));
    });

    test('estimates completed size for multiple native SegWit inputs', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
        amountSat: 150000,
        inputCount: 2,
      );
      final wallet =
          WalletModel.publicBdk(
                id: 'multi-input-size',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;
      expect(bdk.Psbt(psbtBase64: unsignedPsbt).input(), hasLength(2));
      final estimated = datasource.decodeTxSize(unsignedPsbt, wallet: wallet);
      final first = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final second = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 1,
      );
      final finalized = datasource.finalizePsbt(
        datasource.combinePsbts(first: first.psbt, second: second.psbt),
      );
      final exact = bdk.Psbt(psbtBase64: finalized.psbt).extractTx().vsize();

      expect(finalized.isFinalized, isTrue);
      expect(datasource.decodeTxSize(finalized.psbt, wallet: wallet), exact);
      expect(estimated, greaterThanOrEqualTo(exact));
    });

    test('rejects a PSBT belonging to a different descriptor wallet', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final other = singleSignatureDescriptors(testMnemonics.last);
      final wallet =
          WalletModel.publicBdk(
                id: 'other',
                descriptor: twoPathDescriptor(other.external, other.internal),
                isTestnet: true,
              )
              as PublicBdkWalletModel;

      expect(
        () => datasource.inspectPsbt(
          unsignedPsbt,
          wallet: wallet,
          walletFingerprints: {other.fingerprint},
        ),
        throwsA(isA<BitcoinPsbtWalletMismatchException>()),
      );
    });

    test('rejects a PSBT without previous output data', () {
      final psbt = bitcoin_base.Psbt.fromBase64(
        buildUnsignedPsbt(
          descriptor: twoPathDescriptor(
            externalPublicDescriptor,
            internalPublicDescriptor,
          ),
        ),
      );
      psbt.input.removeInputKeys(0, [
        bitcoin_base.PsbtInputTypes.nonWitnessUTXO,
        bitcoin_base.PsbtInputTypes.witnessUTXO,
      ]);
      final wallet =
          WalletModel.publicBdk(
                id: 'missing-utxo',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;

      expect(
        () => datasource.inspectPsbt(
          psbt.toBase64(),
          wallet: wallet,
          walletFingerprints: signers
              .map((signer) => signer.fingerprint)
              .toSet(),
        ),
        throwsA(isA<BitcoinPsbtMissingUtxoException>()),
      );
    });

    test('rejects a PSBT that does not commit to every output', () {
      final psbt = bitcoin_base.Psbt.fromBase64(
        buildUnsignedPsbt(
          descriptor: twoPathDescriptor(
            externalPublicDescriptor,
            internalPublicDescriptor,
          ),
        ),
      );
      psbt.input.updateInputs(0, [
        bitcoin_base.PsbtInputSigHash(
          bitcoin_base.BitcoinOpCodeConst.sighashNone,
        ),
      ]);
      final wallet =
          WalletModel.publicBdk(
                id: 'unsafe-sighash',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;

      expect(
        () => datasource.inspectPsbt(
          psbt.toBase64(),
          wallet: wallet,
          walletFingerprints: signers
              .map((signer) => signer.fingerprint)
              .toSet(),
        ),
        throwsA(isA<BitcoinPsbtUnsupportedSighashException>()),
      );
    });

    test('rejects a PSBT containing a forged partial signature', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final signed = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final forged = _replaceSignature(signed.psbt, (signature) {
        signature[signature.length - 2] ^= 0x01;
      });
      final wallet =
          WalletModel.publicBdk(
                id: 'forged-signature',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;

      expect(
        () => datasource.inspectPsbt(
          forged,
          wallet: wallet,
          walletFingerprints: signers
              .map((signer) => signer.fingerprint)
              .toSet(),
        ),
        throwsA(isA<InvalidBitcoinPsbtException>()),
      );
    });

    test('rejects a PSBT containing an undisclosed unsafe signature', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final signed = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final unsafe = _replaceSignature(
        signed.psbt,
        (signature) => signature[signature.length - 1] =
            bitcoin_base.BitcoinOpCodeConst.sighashSingle,
      );
      final wallet =
          WalletModel.publicBdk(
                id: 'unsafe-signature',
                descriptor: twoPathDescriptor(
                  externalPublicDescriptor,
                  internalPublicDescriptor,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;

      expect(
        () => datasource.inspectPsbt(
          unsafe,
          wallet: wallet,
          walletFingerprints: signers
              .map((signer) => signer.fingerprint)
              .toSet(),
        ),
        throwsA(isA<BitcoinPsbtUnsupportedSighashException>()),
      );
    });

    test('finalizes only after combining enough partial signatures', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final firstSignature = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final secondSignature = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 1,
      );

      expect(firstSignature.isFinalized, isFalse);
      final partial = datasource.finalizePsbt(firstSignature.psbt);
      expect(partial.isFinalized, isFalse);
      expect(signedFingerprints(partial.psbt), {
        signers.first.fingerprint.toLowerCase(),
      });

      final combined = datasource.combinePsbts(
        first: firstSignature.psbt,
        second: secondSignature.psbt,
      );

      expect(datasource.finalizePsbt(combined).isFinalized, isTrue);
    });

    for (final scriptType in [
      (name: 'nested SegWit', wrap: (String multisig) => 'sh(wsh($multisig))'),
      (name: 'legacy', wrap: (String multisig) => 'sh($multisig)'),
    ]) {
      test('round-trips ${scriptType.name} multisig signing', () {
        String descriptor({required bool internal, int? privateSignerIndex}) {
          final keys = [
            for (final (index, signer) in signers.indexed)
              if (internal)
                index == privateSignerIndex
                    ? signer.internalPrivate
                    : signer.internalPublic
              else
                index == privateSignerIndex
                    ? signer.externalPrivate
                    : signer.externalPublic,
          ];
          return scriptType.wrap('sortedmulti(2,${keys.join(',')})');
        }

        final publicDescriptor = twoPathDescriptor(
          descriptor(internal: false),
          descriptor(internal: true),
        );
        final parsed = BdkFacade.parsePublicTwoPathDescriptor(
          descriptor: publicDescriptor,
          isTestnet: true,
        );
        final wallet =
            WalletModel.publicBdk(
                  id: '${scriptType.name}-multisig',
                  descriptor: publicDescriptor,
                  isTestnet: true,
                )
                as PublicBdkWalletModel;
        final policy = BitcoinWalletPolicyMapper.toEntity(
          datasource.analyzePolicy(wallet: wallet),
        );
        final unsignedPsbt = buildUnsignedPsbt(descriptor: publicDescriptor);
        final firstSignature = datasource.signPsbtWithDescriptor(
          unsignedPsbt,
          descriptor: twoPathDescriptor(
            descriptor(internal: false, privateSignerIndex: 0),
            descriptor(internal: true, privateSignerIndex: 0),
          ),
          isTestnet: true,
        );
        final secondSignature = datasource.signPsbtWithDescriptor(
          unsignedPsbt,
          descriptor: twoPathDescriptor(
            descriptor(internal: false, privateSignerIndex: 1),
            descriptor(internal: true, privateSignerIndex: 1),
          ),
          isTestnet: true,
        );
        final combined = datasource.combinePsbts(
          first: firstSignature.psbt,
          second: secondSignature.psbt,
        );

        expect(parsed.keys, hasLength(signers.length));
        expect(policy.external.root, isA<BitcoinThresholdPolicyNode>());
        expect(firstSignature.isFinalized, isFalse);
        expect(datasource.finalizePsbt(combined).isFinalized, isTrue);
      });
    }

    test('signs a selected branch through nested policy thresholds', () {
      final externalPublic = _nestedPolicyDescriptor([
        signers[0].externalPublic,
        signers[1].externalPublic,
        signers[2].externalPublic,
      ]);
      final internalPublic = _nestedPolicyDescriptor([
        signers[0].internalPublic,
        signers[1].internalPublic,
        signers[2].internalPublic,
      ]);
      final wallet =
          WalletModel.publicBdk(
                id: 'nested-policy',
                descriptor: twoPathDescriptor(externalPublic, internalPublic),
                isTestnet: true,
              )
              as PublicBdkWalletModel;
      final policy = BitcoinWalletPolicyMapper.toEntity(
        datasource.analyzePolicy(wallet: wallet),
      );
      var selection = const BitcoinPolicySelection.empty();
      for (var depth = 0; depth < 2; depth++) {
        final requirement = policy.pathRequirements(selection).first;
        selection = policy.select(
          current: selection,
          requirement: requirement,
          selectedIndices: {requirement.nodePath == 'root' ? 1 : 0},
        );
      }

      expect(policy.pathRequirements(selection), isEmpty);
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(externalPublic, internalPublic),
        policyPath: policy.buildPath(selection),
      );
      final signed = datasource.signPsbtWithDescriptor(
        unsignedPsbt,
        descriptor: twoPathDescriptor(
          _nestedPolicyDescriptor([
            signers[0].externalPublic,
            signers[1].externalPrivate,
            signers[2].externalPrivate,
          ]),
          _nestedPolicyDescriptor([
            signers[0].internalPublic,
            signers[1].internalPrivate,
            signers[2].internalPrivate,
          ]),
        ),
        isTestnet: true,
      );

      expect(signed.isFinalized, isTrue);
    });

    test('accepts a cryptographically valid added partial signature', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final signed = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );

      expect(
        () => datasource.validateExternalPartialPsbt(
          currentPsbtBase64: unsignedPsbt,
          signedPsbtBase64: signed.psbt,
        ),
        returnsNormally,
      );
    });

    test('rejects a forged partial signature', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final signed = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final forged = _replaceSignature(signed.psbt, (signature) {
        signature[signature.length - 2] ^= 0x01;
      });

      expect(
        () => datasource.validateExternalPartialPsbt(
          currentPsbtBase64: unsignedPsbt,
          signedPsbtBase64: forged,
        ),
        throwsA(isA<InvalidBitcoinPsbtException>()),
      );
    });

    for (final (label, sighash, addContradictoryAllField) in [
      ('SIGHASH_NONE', bitcoin_base.BitcoinOpCodeConst.sighashNone, false),
      ('SIGHASH_SINGLE', bitcoin_base.BitcoinOpCodeConst.sighashSingle, true),
      (
        'SIGHASH_ALL|ANYONECANPAY',
        bitcoin_base.BitcoinOpCodeConst.sighashAll |
            bitcoin_base.BitcoinOpCodeConst.sighashAnyoneCanPay,
        false,
      ),
    ]) {
      test('rejects actual $label when the metadata does not disclose it', () {
        final unsignedPsbt = buildUnsignedPsbt(
          descriptor: twoPathDescriptor(
            externalPublicDescriptor,
            internalPublicDescriptor,
          ),
        );
        final signed = signPsbt(
          datasource,
          unsignedPsbt,
          signers: signers,
          signerIndex: 0,
        );
        final unsafe = _replaceSignature(
          signed.psbt,
          (signature) => signature[signature.length - 1] = sighash,
          addSighashAllField: addContradictoryAllField,
        );

        expect(
          () => datasource.validateExternalPartialPsbt(
            currentPsbtBase64: unsignedPsbt,
            signedPsbtBase64: unsafe,
          ),
          throwsA(isA<BitcoinPsbtUnsupportedSighashException>()),
        );
      });
    }

    test('rejects an externally finalized PSBT input', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final first = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final second = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 1,
      );
      final finalized = datasource.finalizePsbt(
        datasource.combinePsbts(first: first.psbt, second: second.psbt),
      );
      expect(finalized.isFinalized, isTrue);

      expect(
        () => datasource.validateExternalPartialPsbt(
          currentPsbtBase64: unsignedPsbt,
          signedPsbtBase64: finalized.psbt,
        ),
        throwsA(isA<InvalidBitcoinPsbtException>()),
      );
    });

    test('rejects PSBTs containing different unsigned transactions', () {
      final first = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
        amountSat: 50000,
      );
      final second = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
        amountSat: 51000,
      );

      expect(
        () => datasource.combinePsbts(first: first, second: second),
        throwsA(isA<bdk.PsbtException>()),
      );
    });

    test('accepts a final transaction only for the prepared PSBT', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final firstSignature = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 0,
      );
      final secondSignature = signPsbt(
        datasource,
        unsignedPsbt,
        signers: signers,
        signerIndex: 1,
      );
      final combined = datasource.combinePsbts(
        first: firstSignature.psbt,
        second: secondSignature.psbt,
      );
      final finalized = datasource.finalizePsbt(combined);
      final transaction = hex.encode(
        bdk.Psbt(psbtBase64: finalized.psbt).extractTx().serialize(),
      );

      final verified = datasource.verifyFinalTransaction(
        psbtBase64: unsignedPsbt,
        transactionHex: transaction,
      );
      expect(verified.transaction, transaction);
      expect(verified.txSize, greaterThan(0));

      final changedVersion = hex.decode(transaction);
      changedVersion[0] ^= 0x01;
      final substitutedInput = hex.decode(transaction);
      // version (4), SegWit marker/flag (2), input count (1), then prevout.
      substitutedInput[7] ^= 0x01;
      final changedLocktime = hex.decode(transaction);
      changedLocktime[changedLocktime.length - 1] ^= 0x01;
      for (final changedTransaction in [
        changedVersion,
        substitutedInput,
        changedLocktime,
      ]) {
        expect(
          () => datasource.verifyFinalTransaction(
            psbtBase64: unsignedPsbt,
            transactionHex: hex.encode(changedTransaction),
          ),
          throwsFormatException,
        );
      }

      final differentPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
        amountSat: 51000,
      );
      expect(
        () => datasource.verifyFinalTransaction(
          psbtBase64: differentPsbt,
          transactionHex: transaction,
        ),
        throwsFormatException,
      );
    });

    for (final (label, sighash) in [
      ('SIGHASH_NONE', bitcoin_base.BitcoinOpCodeConst.sighashNone),
      ('SIGHASH_SINGLE', bitcoin_base.BitcoinOpCodeConst.sighashSingle),
      (
        'SIGHASH_ALL|ANYONECANPAY',
        bitcoin_base.BitcoinOpCodeConst.sighashAllAnyOneCanPay,
      ),
    ]) {
      test('rejects a final raw transaction containing $label', () {
        final unsignedPsbt = buildUnsignedPsbt(
          descriptor: twoPathDescriptor(
            externalPublicDescriptor,
            internalPublicDescriptor,
          ),
        );
        final first = signPsbt(
          datasource,
          unsignedPsbt,
          signers: signers,
          signerIndex: 0,
        );
        final second = signPsbt(
          datasource,
          unsignedPsbt,
          signers: signers,
          signerIndex: 1,
        );
        final finalized = datasource.finalizePsbt(
          datasource.combinePsbts(first: first.psbt, second: second.psbt),
        );
        final transaction = bdk.Psbt(psbtBase64: finalized.psbt).extractTx();
        final signature = transaction.input().single.witness.firstWhere(
          (item) => item.length >= 9 && item.first == 0x30,
        );
        final bytes = transaction.serialize().toList();
        final signatureOffset = _sublistIndex(bytes, signature);
        expect(signatureOffset, greaterThanOrEqualTo(0));
        bytes[signatureOffset + signature.length - 1] = sighash;

        expect(
          () => datasource.verifyFinalTransaction(
            psbtBase64: unsignedPsbt,
            transactionHex: hex.encode(bytes),
          ),
          throwsFormatException,
        );
      });
    }

    test('rejects an unsigned raw transaction', () {
      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(
          externalPublicDescriptor,
          internalPublicDescriptor,
        ),
      );
      final transaction = hex.encode(
        bdk.Psbt(psbtBase64: unsignedPsbt).extractTx().serialize(),
      );

      expect(
        () => datasource.verifyFinalTransaction(
          psbtBase64: unsignedPsbt,
          transactionHex: transaction,
        ),
        throwsFormatException,
      );
    });
  });

  group('BdkWalletDatasource hashlock satisfaction', () {
    test('validates, inserts and signs a SHA256 preimage', () {
      final preimageHex = List.generate(
        32,
        (index) => index.toRadixString(16).padLeft(2, '0'),
      ).join();
      final hash = sha256.convert(hex.decode(preimageHex)).toString();
      final externalPublic =
          'wsh(and_v(v:pk(${signers[0].externalPublic}),sha256($hash)))';
      final internalPublic =
          'wsh(and_v(v:pk(${signers[0].internalPublic}),sha256($hash)))';
      final externalPrivate =
          'wsh(and_v(v:pk(${signers[0].externalPrivate}),sha256($hash)))';
      final internalPrivate =
          'wsh(and_v(v:pk(${signers[0].internalPrivate}),sha256($hash)))';
      final wallet =
          WalletModel.publicBdk(
                id: 'hashlock',
                descriptor: twoPathDescriptor(externalPublic, internalPublic),
                isTestnet: true,
              )
              as PublicBdkWalletModel;
      final policy = BitcoinWalletPolicyMapper.toEntity(
        datasource.analyzePolicy(wallet: wallet),
      );
      final hashlock = policy
          .requiredHashlocks(const BitcoinPolicySelection.empty())
          .single;
      final preimage = BitcoinPolicyPreimage(
        type: hashlock.type,
        hash: hashlock.hash,
        preimageHex: preimageHex,
      );

      expect(policy.hasHashlock, isTrue);
      expect(datasource.validatePolicyPreimage(preimage), isTrue);
      expect(
        datasource.validatePolicyPreimage(
          BitcoinPolicyPreimage(
            type: hashlock.type,
            hash: hashlock.hash,
            preimageHex: List.filled(32, 'ff').join(),
          ),
        ),
        isFalse,
      );

      final unsignedPsbt = buildUnsignedPsbt(
        descriptor: twoPathDescriptor(externalPublic, internalPublic),
      );
      final withPreimage = datasource.applyPolicyPreimages(unsignedPsbt, [
        preimage,
      ]);
      expect(
        bdk.Psbt(
          psbtBase64: withPreimage,
        ).input().single.sha256Preimages.keys.single,
        hash,
      );
      expect(
        bdk.Psbt(
          psbtBase64: withPreimage,
        ).input().single.sha256Preimages.values.single,
        hex.decode(preimageHex),
      );
      final signed = datasource.signPsbtWithDescriptor(
        withPreimage,
        descriptor: twoPathDescriptor(externalPrivate, internalPrivate),
        isTestnet: true,
      );

      expect(signed.isFinalized, isTrue);
    });
  });
}

String _nestedPolicyDescriptor(List<String> keys) =>
    'wsh(or_d(pk(${keys[0]}),and_v(v:pk(${keys[1]}),'
    'or_i(pk(${keys[2]}),and_v(v:older(10),'
    'sha256(${List.filled(32, '11').join()}))))))';

String _replaceSignature(
  String psbtBase64,
  void Function(List<int> signature) mutate, {
  bool addSighashAllField = false,
}) {
  final psbt = bitcoin_base.Psbt.fromBase64(psbtBase64);
  final partial = psbt.input
      .getInputs<bitcoin_base.PsbtInputPartialSig>(
        0,
        bitcoin_base.PsbtInputTypes.partialSignature,
      )!
      .single;
  final signature = partial.signature.toList();
  mutate(signature);
  psbt.input.updateInputs(0, [
    bitcoin_base.PsbtInputPartialSig(
      signature: signature,
      publicKey: partial.publicKeyBytes,
    ),
    if (addSighashAllField)
      bitcoin_base.PsbtInputSigHash(bitcoin_base.BitcoinOpCodeConst.sighashAll),
  ]);
  return psbt.toBase64();
}

int _sublistIndex(List<int> bytes, List<int> needle) {
  for (var offset = 0; offset <= bytes.length - needle.length; offset++) {
    if (Iterable<int>.generate(
      needle.length,
    ).every((index) => bytes[offset + index] == needle[index])) {
      return offset;
    }
  }
  return -1;
}
