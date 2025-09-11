import 'package:ark_wallet/ark_wallet.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';

class CreateArkWalletUsecase {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  CreateArkWalletUsecase({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  Future<void> execute() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );

    if (wallets.isEmpty) throw 'No default wallet found';
    final defaultWallet = wallets.first;

    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);

    print(seed.bytes);
    print(seed.hex);

    final arkWallet = await ArkWallet.init(
      secretKey: seed.bytes,
      network: 'bitcoin',
      esplora: 'https://mempool.space/api',
      server: 'https://bitcoin-beta.arkade.sh',
    );

    print(arkWallet.offchainAddress());
  }
}
