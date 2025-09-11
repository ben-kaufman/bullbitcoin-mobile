import 'package:bb_mobile/features/ark/setup_page.dart';
import 'package:go_router/go_router.dart';

enum ArkRoute {
  arkSetup('/ark/setup');

  final String path;

  const ArkRoute(this.path);
}

class ArkRouter {
  static final route = GoRoute(
    name: ArkRoute.arkSetup.name,
    path: ArkRoute.arkSetup.path,
    builder: (context, state) => ArkSetupPage(),
  );
}
