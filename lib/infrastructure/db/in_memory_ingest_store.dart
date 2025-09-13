/// In-Memory Ingest Store (Minimal Prototype Implementation)
///
/// Combines:
/// - PlateQueryRepository
/// - UpsertPlanApplier
/// - RecentEventsWindow
///
/// Purpose:
/// Enable running the ingestion use case end-to-end without a real
/// persistence layer. This is strictly for prototyping & early logic
/// validation (NOT production safe).
///
/// Characteristics:
/// - Not thread-safe (single isolate usage assumed)
/// - No eviction / size bounds beyond recent events window cap
/// - No logging / metrics
/// - Uses simple Maps keyed by normalized plate or id
///
/// Future Replacement:
/// A real implementation will live in a SQLite-backed repository that
/// maps domain upsert plans into transactional SQL operations.
///
/// References:
/// - lib/app/usecases/ingest_frame_usecase.dart
/// - lib/domain/plate_entities.dart
///
/// Keep this file small and easily disposable.
///
/// NOTE: NEW IDs must be generated *outside* via the provided PlateIdProvider
/// inside the use case; this store trusts the plans it receives.
library in_memory_ingest_store;

import 'package:plate_runner/domain/plate_entities.dart';
import 'package:plate_runner/app/usecases/ingest_frame_usecase.dart';

/// Concrete minimal in-memory store implementing ingestion dependencies.
class InMemoryIngestStore
    implements PlateQueryRepository, UpsertPlanApplier, RecentEventsWindow {
  final Map<String, PlateRecord> _platesByNormalized = {};
  final Map<String, PlateRecord> _platesById = {};
  final Map<String, List<RecognitionEvent>> _eventsByPlateId = {};
  final Map<NormalizedPlate, List<RecognitionEvent>> _recentByPlate = {};

  /// Capacity limit for recent window cache per plate (older evicted).
  final int maxRecentEventsPerPlate;

  InMemoryIngestStore({this.maxRecentEventsPerPlate = 16});

  // --------------------------------------------------------------------------
  // PlateQueryRepository
  // --------------------------------------------------------------------------
  @override
  Future<PlateRecord?> fetchByNormalized(NormalizedPlate plate) async {
    return _platesByNormalized[plate.value];
  }

  // --------------------------------------------------------------------------
  // UpsertPlanApplier
  // --------------------------------------------------------------------------
  @override
  Future<void> applyPlans(List<UpsertPlan> plans) async {
    for (final plan in plans) {
      switch (plan) {
        case InsertNewPlateAndEvent(
            newPlateId: final newId,
            plate: final plate,
            event: final event,
          ):
          final record = PlateRecord(
            id: newId,
            plate: plate,
            firstSeen: event.timestamp,
            lastSeen: event.timestamp,
            totalRecognitions: 1,
          );
          _platesByNormalized[plate.value] = record;
          _platesById[newId.value] = record;
          _eventsByPlateId.putIfAbsent(newId.value, () => <RecognitionEvent>[]).add(event);

        case InsertEventAndUpdatePlate(
            updatedPlate: final updated,
            event: final event,
          ):
          _platesByNormalized[updated.plate.value] = updated;
            _platesById[updated.id.value] = updated;
          _eventsByPlateId
              .putIfAbsent(updated.id.value, () => <RecognitionEvent>[])
              .add(event);
      }
    }
  }

  // --------------------------------------------------------------------------
  // RecentEventsWindow
  // --------------------------------------------------------------------------
  @override
  List<RecognitionEvent> eventsForPlate(NormalizedPlate plate) {
    final list = _recentByPlate[plate];
    return list == null ? const [] : List.unmodifiable(list);
  }

  @override
  void addEvents(List<RecognitionEvent> events) {
    for (final e in events) {
      final bucket = _recentByPlate.putIfAbsent(e.plate, () => <RecognitionEvent>[]);
      bucket.add(e);
      if (bucket.length > maxRecentEventsPerPlate) {
        // Evict oldest events (simple FIFO trim)
        bucket.removeRange(0, bucket.length - maxRecentEventsPerPlate);
      }
    }
  }

  /// Optional maintenance: prune recent events older than [cutoffEpochMs].
  void pruneOlderThan(int cutoffEpochMs) {
    for (final entry in _recentByPlate.entries) {
      entry.value.removeWhere((e) => e.timestamp < cutoffEpochMs);
    }
  }

  // --------------------------------------------------------------------------
  // Convenience Inspection (Debug Only)
  // --------------------------------------------------------------------------

  /// Returns a lightweight snapshot for debugging / manual inspection.
  Map<String, Object?> debugSnapshot() {
    final totalEvents = _eventsByPlateId.values.fold<int>(
      0,
      (acc, list) => acc + list.length,
    );
    return {
      'plates': _platesByNormalized.length,
      'eventsTotal': totalEvents,
      'recentWindowPlates': _recentByPlate.length,
    };
  }

  /// Lists all stored plate records (debug only).
  List<PlateRecord> debugAllPlates() =>
      List.unmodifiable(_platesByNormalized.values);

  /// Lists events for a given plate id (debug only).
  List<RecognitionEvent> debugEventsForPlateId(PlateId id) =>
      List.unmodifiable(_eventsByPlateId[id.value] ?? const []);

  /// Clear all stored data (useful for resetting in a manual harness).
  void clearAll() {
    _platesByNormalized.clear();
    _platesById.clear();
    _eventsByPlateId.clear();
    _recentByPlate.clear();
  }
}