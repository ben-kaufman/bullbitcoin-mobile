import 'package:bb_mobile/core/failures/failure.dart';

sealed class PsbtSigningFailure extends Failure {
  const PsbtSigningFailure([super.logMessage]);
}

final class PsbtSigningWalletUnavailableFailure extends PsbtSigningFailure {
  const PsbtSigningWalletUnavailableFailure([super.logMessage]);
}

final class PsbtSigningInvalidPsbtFailure extends PsbtSigningFailure {
  const PsbtSigningInvalidPsbtFailure([super.logMessage]);
}

final class PsbtSigningWalletMismatchFailure extends PsbtSigningFailure {
  const PsbtSigningWalletMismatchFailure([super.logMessage]);
}

final class PsbtSigningMissingLocalKeyFailure extends PsbtSigningFailure {
  const PsbtSigningMissingLocalKeyFailure([super.logMessage]);
}

final class PsbtSigningMissingUtxoFailure extends PsbtSigningFailure {
  const PsbtSigningMissingUtxoFailure([super.logMessage]);
}

final class PsbtSigningUnsupportedSighashFailure extends PsbtSigningFailure {
  const PsbtSigningUnsupportedSighashFailure([super.logMessage]);
}

final class PsbtSigningUnsupportedSpendModeFailure extends PsbtSigningFailure {
  const PsbtSigningUnsupportedSpendModeFailure([super.logMessage]);
}

final class PsbtSigningNoSignatureAddedFailure extends PsbtSigningFailure {
  const PsbtSigningNoSignatureAddedFailure([super.logMessage]);
}

final class PsbtSigningUnexpectedFailure extends PsbtSigningFailure {
  const PsbtSigningUnexpectedFailure([super.logMessage]);
}
