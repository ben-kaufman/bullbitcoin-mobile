import 'package:bb_mobile/core/utils/descriptor_derivation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../bdk_wallet_test_fixture.dart';

void main() {
  late List<SignerDescriptorKeys> signers;

  setUpAll(() {
    signers = testMnemonics.map(deriveSignerKeys).toList();
  });

  group('DescriptorDerivation sorted multisig', () {
    test('supports configurable thresholds and key counts', () {
      final twoOfTwo =
          DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
            threshold: 2,
            descriptorKeys: signers
                .take(2)
                .map((signer) => signer.externalPublic)
                .toList(),
          );
      final threeOfThree =
          DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
            threshold: 3,
            descriptorKeys: signers
                .map((signer) => signer.externalPublic)
                .toList(),
          );

      expect(twoOfTwo, startsWith('wsh(sortedmulti(2,'));
      expect(threeOfThree, startsWith('wsh(sortedmulti(3,'));
    });

    test('rejects invalid thresholds', () {
      expect(
        () => DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
          threshold: 0,
          descriptorKeys: signers
              .map((signer) => signer.externalPublic)
              .toList(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate keys', () {
      expect(
        () => DescriptorDerivation.derivePublicBitcoinSortedMultisigDescriptor(
          threshold: 2,
          descriptorKeys: [
            signers.first.externalPublic,
            signers.first.externalPublic,
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
