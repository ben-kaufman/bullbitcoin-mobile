import 'dart:convert';

import 'package:bb_mobile/core/utils/bitcoin_signer_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const psbt =
      'cHNidP8BAFICAAAAARERERERERERERERERERERERERERERERERERERERERERAAAAAAD9'
      '////AaCGAQAAAAAAFgAUIiIiIiIiIiIiIiIiIiIiIiIiIiIAAAAAAAEBH2iHAQAAAAAAFgAU'
      'MzMzMzMzMzMzMzMzMzMzMzMzMzMAAA==';
  const transaction =
      '020000000111111111111111111111111111111111111111111111111111111111'
      '111111110000000000fdffffff01a0860100000000001600142222222222222222'
      '22222222222222222222222200000000';

  test('canonicalizes a signed PSBT', () {
    expect(parseBitcoinSignerResult(psbt), (
      format: BitcoinSignerResultFormat.psbt,
      value: psbt,
    ));
  });

  test('normalizes a final transaction', () {
    expect(parseBitcoinSignerResult('  ${transaction.toUpperCase()}  '), (
      format: BitcoinSignerResultFormat.transaction,
      value: transaction,
    ));
  });

  test('rejects hex that is not a transaction', () {
    expect(() => parseBitcoinSignerResult('02000000aa'), throwsFormatException);
  });

  test('rejects an unsupported signer result', () {
    expect(
      () => parseBitcoinSignerResult('not a transaction'),
      throwsFormatException,
    );
  });

  group('PSBT resource boundaries', () {
    test('accepts exactly the decoded size cap', () {
      final bytes = <int>[0x70, 0x73, 0x62, 0x74, 0xff];
      bytes.addAll(
        List<int>.filled(maxBitcoinPsbtDecodedBytes - bytes.length, 0),
      );

      expect(base64.decode(normalizeBitcoinPsbt(base64.encode(bytes))), bytes);
    });

    test('rejects one byte over the decoded size cap', () {
      final bytes = <int>[0x70, 0x73, 0x62, 0x74, 0xff];
      bytes.addAll(
        List<int>.filled(maxBitcoinPsbtDecodedBytes + 1 - bytes.length, 0),
      );

      expect(
        () => normalizeBitcoinPsbt(base64.encode(bytes)),
        throwsFormatException,
      );
    });

    test('rejects input over the transport cap before decoding', () {
      expect(
        () => normalizeBitcoinPsbt(
          'A'.padRight(maxBitcoinPsbtTransportBytes + 1, 'A'),
        ),
        throwsFormatException,
      );
    });

    test('accepts base64 file contents larger than the decoded cap', () {
      final decoded = <int>[0x70, 0x73, 0x62, 0x74, 0xff];
      decoded.addAll(List<int>.filled(1600000 - decoded.length, 0));
      final encodedFileBytes = utf8.encode(base64.encode(decoded));
      expect(encodedFileBytes.length, greaterThan(maxBitcoinPsbtDecodedBytes));

      expect(
        base64.decode(decodeBitcoinPsbtFileBytes(encodedFileBytes)),
        decoded,
      );
    });

    test('rejects oversized binary file contents at decoded boundary', () {
      final bytes = <int>[0x70, 0x73, 0x62, 0x74, 0xff];
      bytes.addAll(
        List<int>.filled(maxBitcoinPsbtDecodedBytes + 1 - bytes.length, 0),
      );

      expect(() => decodeBitcoinPsbtFileBytes(bytes), throwsFormatException);
    });
  });
}
