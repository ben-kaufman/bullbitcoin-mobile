import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/send/data/pending_bitcoin_transaction_datasource.dart';
import 'package:bb_mobile/features/send/data/pending_bitcoin_transaction_mapper.dart';
import 'package:bb_mobile/features/send/domain/pending_bitcoin_transaction.dart';
import 'package:bb_mobile/features/send/domain/repositories/pending_bitcoin_transaction_repository.dart';
import 'package:bb_mobile/features/send/domain/send_failure.dart';

class PendingBitcoinTransactionRepositoryImpl
    implements PendingBitcoinTransactionRepository {
  final PendingBitcoinTransactionDatasource _datasource;

  const PendingBitcoinTransactionRepositoryImpl(this._datasource);

  @override
  Future<Result<PendingBitcoinTransaction, SendFailure>> save(
    PendingBitcoinTransaction transaction, {
    DateTime? expectedUpdatedAt,
  }) async {
    try {
      final saved = await _datasource.save(
        PendingBitcoinTransactionMapper.toModel(transaction),
        expectedUpdatedAt: expectedUpdatedAt,
      );
      return Ok(PendingBitcoinTransactionMapper.toEntity(saved));
    } on PendingBitcoinTransactionChangedException catch (_, stackTrace) {
      log.warning(
        'A stale pending Bitcoin transaction update was rejected',
        trace: stackTrace,
      );
      return const Err(SendPendingTransactionChangedFailure());
    } on Exception catch (error, stackTrace) {
      log.severe(
        message: 'Failed to save a pending Bitcoin transaction',
        error: error.runtimeType,
        trace: stackTrace,
      );
      return const Err(SendPersistenceFailure());
    }
  }

  @override
  Future<Result<PendingBitcoinTransaction?, SendFailure>> get(String id) async {
    try {
      final model = await _datasource.get(id);
      return Ok(
        model == null ? null : PendingBitcoinTransactionMapper.toEntity(model),
      );
    } on Exception catch (error, stackTrace) {
      log.severe(
        message: 'Failed to load a pending Bitcoin transaction',
        error: error.runtimeType,
        trace: stackTrace,
      );
      return const Err(SendPersistenceFailure());
    }
  }

  @override
  Stream<Result<PendingBitcoinTransactionSnapshot, SendFailure>> watchWallet(
    String walletId,
  ) async* {
    try {
      await for (final models in _datasource.watchWallet(walletId)) {
        final transactions = <PendingBitcoinTransaction>[];
        var invalidCount = 0;
        for (final model in models) {
          try {
            transactions.add(PendingBitcoinTransactionMapper.toEntity(model));
          } on Object catch (error, stackTrace) {
            invalidCount++;
            log.warning(
              'Ignored an invalid pending Bitcoin transaction',
              error: error.runtimeType,
              trace: stackTrace,
            );
          }
        }
        yield Ok(
          PendingBitcoinTransactionSnapshot(
            transactions: transactions,
            invalidCount: invalidCount,
          ),
        );
      }
    } on Exception catch (error, stackTrace) {
      log.severe(
        message: 'Failed to watch pending Bitcoin transactions',
        error: error.runtimeType,
        trace: stackTrace,
      );
      yield const Err(SendPersistenceFailure());
    }
  }

  @override
  Future<Result<void, SendFailure>> delete(String id) async {
    try {
      await _datasource.delete(id);
      return const Ok(null);
    } on Exception catch (error, stackTrace) {
      log.severe(
        message: 'Failed to delete a pending Bitcoin transaction',
        error: error.runtimeType,
        trace: stackTrace,
      );
      return const Err(SendPersistenceFailure());
    }
  }
}
