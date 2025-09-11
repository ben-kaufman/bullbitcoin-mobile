import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/features/ark/create_ark_wallet_usecase.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ArkSetupPage extends StatelessWidget {
  final _createArkWalletUsecase = locator<CreateArkWalletUsecase>();

  ArkSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    // const bip85Length = 32;
    // const bip85Index = 11811;

    return Scaffold(
      appBar: AppBar(title: const Text('Ark Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('''
Ark is still experimental. We are going to create a new Ark wallet using your default mnemonic.

By continuing, you acknowledge the risk of losing funds if you have not properly backed up both your default mnemonic.
            '''),
            BBButton.big(
              onPressed: () {
                _createArkWalletUsecase.execute();
                context.goNamed(WalletRoute.walletHome.name);
              },
              label: 'Enable Ark',
              bgColor: context.colour.primary,
              textColor: context.colour.onPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
