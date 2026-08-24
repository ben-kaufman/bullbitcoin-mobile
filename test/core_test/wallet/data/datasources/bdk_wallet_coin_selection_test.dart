import 'dart:io';
import 'dart:typed_data';

import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_facade.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_utxo_model.dart';
import 'package:bb_mobile/core/wallet/domain/bitcoin_coin_selection_exception.dart';
import 'package:bull_sdk/bdk.dart' as bdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../bdk_wallet_test_fixture.dart';

final class _TestPathProvider extends PathProviderPlatform {
  final String path;

  _TestPathProvider(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync(
      'bdk_coin_selection_test',
    );
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(tempDirectory.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    tempDirectory.deleteSync(recursive: true);
  });

  test(
    'does not add another wallet coin to an insufficient selection',
    () async {
      final descriptors = singleSignatureDescriptors(testMnemonics.first);
      final walletModel =
          WalletModel.publicBdk(
                id: 'manual-selection',
                descriptor: twoPathDescriptor(
                  descriptors.external,
                  descriptors.internal,
                ),
                isTestnet: true,
              )
              as PublicBdkWalletModel;
      final wallet = await BdkFacade.createWallet(walletModel);
      final receivingAddress = wallet.peekAddress(
        keychain: bdk.KeychainKind.external_,
        index: 0,
      );
      wallet.applyUnconfirmedTxs(
        unconfirmedTxs: [
          bdk.UnconfirmedTx(
            tx: fundingTransaction(
              receivingAddress.address.scriptPubkey(),
              previousTxByte: 0x31,
            ),
            lastSeen: 1,
          ),
          bdk.UnconfirmedTx(
            tx: fundingTransaction(
              receivingAddress.address.scriptPubkey(),
              previousTxByte: 0x32,
            ),
            lastSeen: 2,
          ),
        ],
      );
      await BdkFacade.saveWallet(wallet, walletModel.hexId);
      final selected = wallet.listUnspent().first;
      final recipient = wallet.peekAddress(
        keychain: bdk.KeychainKind.external_,
        index: 1,
      );
      final recipientAddress = recipient.address.toString();
      final receivingAddressString = receivingAddress.address.toString();
      wallet.dispose();

      final datasource = BdkWalletDatasource();
      await expectLater(
        datasource.buildPsbt(
          address: recipientAddress,
          amountSat: 150000,
          networkFee: const NetworkFee.absolute(1000),
          selected: [
            WalletUtxoModel.bitcoin(
              txId: selected.outpoint.txid.toString(),
              vout: selected.outpoint.vout,
              amountSat: BigInt.from(100000),
              scriptPubkey: Uint8List(0),
              address: receivingAddressString,
              isExternalKeyChain: true,
            ),
          ],
          wallet: walletModel,
        ),
        throwsA(isA<SelectedBitcoinCoinsInsufficientException>()),
      );
    },
  );
}
