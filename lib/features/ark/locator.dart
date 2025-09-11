import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/ark/create_ark_wallet_usecase.dart';
import 'package:bb_mobile/locator.dart';

class ArkLocator {
  static void setup() {
    locator.registerFactory<CreateArkWalletUsecase>(
      () => CreateArkWalletUsecase(
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
      ),
    );
  }
}
