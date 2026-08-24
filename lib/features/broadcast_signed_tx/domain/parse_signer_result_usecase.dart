import 'package:bb_mobile/core/utils/bitcoin_signer_result.dart';

class ParseSignerResultUsecase {
  const ParseSignerResultUsecase();

  String execute(String result) => parseBitcoinSignerResult(result).value;
}
