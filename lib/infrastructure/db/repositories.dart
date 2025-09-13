/// Persistence Repository Interfaces & Utilities (Scaffold)
///
/// These abstractions define the boundary between the *imperative shell*
/// (SQLite or any other storage engine implementation) and the domain /
/// application orchestration code. They intentionally expose behavior in
/// coarse operations aligned with pipeline upsert semantics instead of
/// leaking low-level SQL concerns.
///
/// Design Principles:
/// - Keep interfaces small & capability-focused.
/// - Favor batch / atomic operations where the domain expects consistency.
/// - Avoid exposing nullable primitives for optional data; use richer domain
///   value objects upstream. (We reuse immutable domain types directly.)
/// - No direct dependency on Flutter; pure Dart only.
/// - Errors map to structured `PersistenceException` subclasses.
///
/// Docs References:
/// - docs/data/persistence.md
/// - docs/data/domain_model.md
/// - docs/architecture/overview.md
/// - docs/architecture/pipeline.md
///
/// NOTE: Implementations live under `infrastructure/db/` (e.g.,
/// `sqlite_repositories.dart`) and must translate low-level driver exceptions
/// into `PersistenceException` hierarchies defined below.
///
/// Future Expansion (not in MVP):
/// - Streaming change feeds (watch queries)
/// - Advanced search / FTS
/// - Incremental compaction / purge policies
library repositories;

import 'package:plate_runner/domain/plate_entities.dart';

/// Base persistence exception type.
sealed class PersistenceException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
  const PersistenceException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() =>
      '$runtimeType(message="$message"${cause != null ? ', cause=$cause' : ''})';
}

/// Thrown when an entity cannot be found where it is required.
class NotFoundException extends PersistenceException {
  const NotFoundException(String message, {Object? cause, StackTrace? stackTrace})
      : super(message, cause: cause, stackTrace: stackTrace);
}

/// Thrown for low-level driver / IO errors (SQLite error codes, etc.).
class DriverException extends PersistenceException {
  const DriverException(String message, {Object? cause, StackTrace? stackTrace})
      : super(message, cause: cause, stackTrace: stackTrace);
}

/// Thrown when an operation violates integrity (unique, FK, invariant).
class IntegrityException extends PersistenceException {
  const IntegrityException(String message,
      {Object? cause, StackTrace? stackTrace})
      : super(message, cause: cause, stackTrace: stackTrace);
}

/// Thrown for timeouts or lock contention exhaustion.
class ConcurrencyException extends PersistenceException {
  const ConcurrencyException(String message,
      {Object? cause, StackTrace? stackTrace})
      : super(message, cause: cause, stackTrace: stackTrace);
}

/// Encapsulates a unit-of-work / transaction boundary.
abstract interface class TransactionRunner {
  /// Execute [action] inside a transaction.
  ///
  /// Implementation ensures:
  /// - BEGIN (immediate / exclusive as appropriate)
  /// - `action()` executes
  /// - COMMIT on success
  /// - ROLLBACK on failure
  ///
  /// If [action] throws a [PersistenceException] it is rethrown after rollback.
  /// Any other exception type is wrapped in a DriverException if not already
  /// a PersistenceException.
  Future<T> inTransaction<T>(Future<T> Function() action);
}

/// CRUD + aggregate operations for plates.
abstract interface class PlateRepository {
  /// Fetch aggregate record by normalized plate text.
  Future<PlateRecord?> findByNormalized(NormalizedPlate normalized);

  /// Fetch aggregate by ID.
  Future<PlateRecord?> findById(PlateId id);

  /// Insert a new plate aggregate (first event already represented inside fields).
  Future<void> insertPlate(PlateRecord plate);

  /// Update aggregate fields after insertion of a new recognition event.
  /// `newLastSeen` must be >= existing lastSeen; implementer SHOULD enforce.
  Future<void> updatePlateAggregate({
    required PlateId id,
    required EpochMs newLastSeen,
    required int incrementRecognitions,
  });

  /// Delete a plate and cascade (if database constraints handle events).
  Future<void> deletePlate(PlateId id);

  /// Return most recently seen plates limited by [limit].
  Future<List<PlateRecord>> recentPlates({required int limit, int offset = 0});
}

/// Insert-only repository for recognition events (no updates expected).
abstract interface class RecognitionEventRepository {
  /// Insert a single recognition event referencing an existing plate id.
  Future<void> insertEvent(RecognitionEvent event);

  /// Insert many events in a batch (within existing txn if any).
  Future<void> insertEvents(List<RecognitionEvent> events);

  /// List recent events for a given plate (paged, descending by timestamp).
  Future<List<RecognitionEvent>> eventsForPlate(
    PlateId id, {
    required int limit,
    int offset = 0,
  });

  /// Count events for a plate (consistency / diagnostics).
  Future<int> countForPlate(PlateId id);

  /// Purge all events for a plate (returns number deleted).
  Future<int> deleteEventsForPlate(PlateId id);
}

/// Composite repository applying domain upsert plans atomically.
/// This isolates the multi-step logic (lookup/create/update + event insert)
/// inside the persistence layer, allowing the application layer to
/// simply pass plans produced by pure domain logic.
abstract interface class UpsertPlanRepository {
  /// Apply a batch of upsert plans atomically.
  ///
  /// Behavior:
  /// - For each `InsertNewPlateAndEvent`: insert plate, then event, then update aggregate
  ///   fields if necessary (some ORMs may require a follow-up).
  /// - For each `InsertEventAndUpdatePlate`: insert event, update aggregate fields.
  /// - The entire batch is one transaction for consistency and fewer fsyncs.
  ///
  /// Implementer MUST:
  /// - Resolve races on normalized unique constraint (retry small bounded).
  /// - Convert low-level constraint failures -> IntegrityException.
  Future<void> applyPlans(List<UpsertPlan> plans);
}

/// Read-only composite facade used by ingestion orchestration where we
/// only need "query by normalized" + "apply upsert plans".
abstract interface class IngestionPersistenceFacade {
  Future<PlateRecord?> findByNormalized(NormalizedPlate normalized);
  Future<void> applyPlans(List<UpsertPlan> plans);
}

/// Simple in-memory recent events window (interface already defined in
/// use case layer). Provided here as a convenience implementation for
/// testing or ephemeral runtime without DB reads.
/// (Concrete class kept tiny; production may rely on DB queries instead.)
abstract interface class RecentEventsCache {
  void addEvents(List<RecognitionEvent> events);
  List<RecognitionEvent> eventsForPlate(NormalizedPlate plate);
  void pruneOlderThan(EpochMs cutoff);
}

/// Health metrics surface for persistence layer (optional collection).
class PersistenceHealthSnapshot {
  final int openConnections;
  final Duration? lastTxnLatencyP95;
  final int pendingWriteQueue;
  final DateTime capturedAt;

  const PersistenceHealthSnapshot({
    required this.openConnections,
    required this.pendingWriteQueue,
    required this.capturedAt,
    this.lastTxnLatencyP95,
  });
}

/// Optional health provider interface (future).
abstract interface class PersistenceHealthProvider {
  Future<PersistenceHealthSnapshot> snapshot();
}

/// Utility: classify an exception (best-effort). Implementation files may use
/// this to map driver-specific errors to domain-neutral categories.
PersistenceException mapUnknownException(Object error, StackTrace st) {
  if (error is PersistenceException) return error;
  // Placeholder heuristics (refine with driver error codes).
  final msg = error.toString().toLowerCase();
  if (msg.contains('lock') || msg.contains('busy')) {
    return ConcurrencyException('Lock contention: $error', cause: error, stackTrace: st);
  }
  if (msg.contains('unique') || msg.contains('constraint')) {
    return IntegrityException('Integrity violation: $error', cause: error, stackTrace: st);
  }
  return DriverException('Driver error: $error', cause: error, stackTrace: st);
}

/// Helper to pretty-print upsert plans for debugging / logging.
String debugDescribePlans(List<UpsertPlan> plans) {
  final buf = StringBuffer('UpsertPlans[');
  for (var i = 0; i < plans.length; i++) {
    final p = plans[i];
    switch (p) {
      case InsertNewPlateAndEvent(:final plate, :final event):
        buf.write(
            'New{plate=${plate.value}, ts=${event.timestamp}, conf=${event.confidence.value.toStringAsFixed(3)}}');
      case InsertEventAndUpdatePlate(:final updatedPlate, :final event):
        buf.write(
            'Existing{id=${updatedPlate.id.value}, plate=${updatedPlate.plate.value}, ts=${event.timestamp}, newTotal=${updatedPlate.totalRecognitions}}');
    }
    if (i != plans.length - 1) buf.write(', ');
  }
  buf.write(']');
  return buf.toString();
}

/// MVP placeholder in-memory implementation of [RecentEventsCache].
/// Not thread-safe; intended for single-threaded test harness or prototype.
class InMemoryRecentEventsCache implements RecentEventsCache {
  final int maxEventsPerPlate;
  final Map<NormalizedPlate, List<RecognitionEvent>> _byPlate = {};
  InMemoryRecentEventsCache({this.maxEventsPerPlate = 32});
  @override
  void addEvents(List<RecognitionEvent> events) {
    for (final e in events) {
      final list = _byPlate.putIfAbsent(e.plate, () => <RecognitionEvent>[]);
      list.add(e);
      if (list.length > maxEventsPerPlate) {
        list.removeRange(0, list.length - maxEventsPerPlate);
      }
    }
  }

  @override
  List<RecognitionEvent> eventsForPlate(NormalizedPlate plate) =>
      List.unmodifiable(_byPlate[plate] ?? const []);

  @override
  void pruneOlderThan(EpochMs cutoff) {
    for (final entry in _byPlate.entries) {
      entry.value.removeWhere((e) => e.timestamp < cutoff);
    }
  }
}