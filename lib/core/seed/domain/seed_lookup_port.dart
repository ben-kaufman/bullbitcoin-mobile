import 'package:bb_mobile/core/seed/domain/entity/seed.dart';

abstract interface class SeedLookupPort {
  Future<Seed> get(String fingerprint);

  Future<bool> exists(String fingerprint);
}
