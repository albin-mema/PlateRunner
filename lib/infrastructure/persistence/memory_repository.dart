/// In-Memory Persistence Repository (Scaffold)
///
/// Purpose:
///   Provide a lightweight, dependency-free persistence abstraction for
///   early pipeline integration & tests before SQLite layer lands.
///   Implements pure-Dart in-memory storage of Plates and RecognitionEvents
///   with atomic-like UpsertPlan application mirroring the intended DB flow.
///
/// Scope (MVP):
///   - Apply `UpsertPlan` variants from domain layer
///   - Maintain maps for fast lookup by PlateId + normalized plate
///   - Track ordered events per plate (append-only list)
///   - Expose query helpers (lookup, recent plates, plate history)
///   - Emit change stream for observers (UI / caches)
///
/// Non-Goals (Until Real DB):
///   - Persistence across app restarts
///   - Sophisticated indexing / pruning
///   - Concurrency safety across isolates (single isolate assumed)
///
/// Concurrency:
///   - Simple synchronous critical sections (single isolate assumption)
///   - If multi-isolate or async heavy usage arises, introduce a queue or
///     synchronization primitive adapter.
///
/// Streams:
///   - `changes` emits `MemoryRepoEvent` whenever a plate or event is added.
///
/// Usage:
/// ```dart
/// final repo = InMemoryPlateRepository();
/// pipeline.plans.listen((p) => repo.applyUpsert(p.plan));
/// final plates = repo.recentPlates(limit: 10);
/// ```
///
/// Extension Points:
///   - Add pruning (retention days) referencing RuntimeConfig
///   - Introduce derived stats caching (PlateStats)
///
/// References:
///   - docs/data/persistence.md
///   - docs/architecture/pipeline.md
library memory_repository;

import 'dart:async';

import 'package:plate_runner/domain/plate_entities.dart';
import 'package:plate_runner/app/pipeline/recognition_pipeline.dart' show PipelineUpsert;

/// Internal model storing plate + mutable recognition list reference.
class _PlateSlot {
  PlateRecord record;
  final List<RecognitionEvent> events;
  _PlateSlot(this.record, this.events);
}

/// Event types emitted by the repository.
sealed class MemoryRepoEvent {
  const MemoryRepoEvent();
}

/// Emitted when a new plate is inserted (first recognition).
class PlateInserted extends MemoryRepoEvent {
  final PlateRecord record;
  const PlateInserted(this.record);
}

/// Emitted when an existing plate is updated (new recognition).
class PlateUpdated extends MemoryRepoEvent {
  final PlateRecord record;
  final RecognitionEvent newEvent;
  const PlateUpdated({required this.record, required this.newEvent});
}

/// Query result for paginated plate history.
class PlateHistoryPage {
  final PlateId plateId;
  final List<RecognitionEvent> events;
  final bool hasMore;
  const PlateHistoryPage({
    required this.plateId,
    required this.events,
    required this.hasMore,
  });
}

/// Repository interface abstraction (subset for MVP).
abstract interface class PlateRepository {
  Stream<MemoryRepoEvent> get changes;

  /// Apply a domain upsert plan. Returns the resulting PlateRecord and the
  /// RecognitionEvent that was inserted.
  (PlateRecord, RecognitionEvent) applyUpsert(UpsertPlan plan);

  /// Lookup by normalized plate value.
  PlateRecord? plateByNormalized(NormalizedPlate plate);

  /// Lookup by PlateId.
  PlateRecord? plateById(PlateId id);

  /// Recent plates ordered by lastSeen descending.
  List<PlateRecord> recentPlates({int limit});

  /// Return a page of recent recognition events for a plate ordered by ts desc.
  PlateHistoryPage plateHistory(
    PlateId id, {
    int limit,
    int offset,
  });

  /// Total counts (plates, recognitions).
  (int plates, int recognitions) stats();

  /// Dispose stream resources.
  Future<void> dispose();
}

/// In-memory implementation.
class InMemoryPlateRepository implements PlateRepository {
  final Map<PlateId, _PlateSlot> _byId = {};
  final Map<String, PlateId> _idByNormalized = {};

  final StreamController<MemoryRepoEvent> _changeCtrl =
      StreamController.broadcast();

  bool _disposed = false;

  @override
  Stream<MemoryRepoEvent> get changes => _changeCtrl.stream;

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Repository disposed');
    }
  }

  @override
  (PlateRecord, RecognitionEvent) applyUpsert(UpsertPlan plan) {
    _ensureNotDisposed();
    switch (plan) {
      case InsertNewPlateAndEvent():
        return _applyInsertNew(plan);
      case InsertEventAndUpdatePlate():
        return _applyUpdateExisting(plan);
    }
  }

  (PlateRecord, RecognitionEvent) _applyInsertNew(
    InsertNewPlateAndEvent plan,
  ) {
    final id = plan.newPlateId;
    if (_byId.containsKey(id)) {
      // This shouldn't normally happen; treat as existing update fallback.
      final existing = _byId[id]!;
      // We still append event (defensive).
      final ev = plan.event.copyWith(plateId: existing.record.id);
      existing.events.add(ev);
      existing.record =
          existing.record.withNewEvent(ev.timestamp); // update stats
      _emit(PlateUpdated(record: existing.record, newEvent: ev));
      return (existing.record, ev);
    }
    final initialRecord = PlateRecord(
      id: id,
      plate: plan.plate,
      firstSeen: plan.event.timestamp,
      lastSeen: plan.event.timestamp,
      totalRecognitions: 1,
    );
    final ev = plan.event.copyWith(plateId: id);
    _byId[id] = _PlateSlot(initialRecord, [ev]);
    _idByNormalized[plan.plate.value] = id;
    _emit(PlateInserted(initialRecord));
    return (initialRecord, ev);
  }

  (PlateRecord, RecognitionEvent) _applyUpdateExisting(
    InsertEventAndUpdatePlate plan,
  ) {
    final id = plan.updatedPlate.id;
    final slot = _byId[id];
    if (slot == null) {
      // If missing (should not normally), treat as new insert path.
      final ev = plan.event;
      final record = plan.updatedPlate;
      _byId[id] = _PlateSlot(record, [ev]);
      _idByNormalized[record.plate.value] = id;
      _emit(PlateInserted(record));
      return (record, ev);
    }

    // Append event & update record (consistent with domain logic).
    final ev = plan.event.copyWith(plateId: slot.record.id);
    slot.events.add(ev);
    slot.record = plan.updatedPlate;
    _emit(PlateUpdated(record: slot.record, newEvent: ev));
    return (slot.record, ev);
  }

  void _emit(MemoryRepoEvent evt) {
    if (!_changeCtrl.isClosed) {
      _changeCtrl.add(evt);
    }
  }

  @override
  PlateRecord? plateByNormalized(NormalizedPlate plate) {
    final id = _idByNormalized[plate.value];
    if (id == null) return null;
    return _byId[id]?.record;
  }

  @override
  PlateRecord? plateById(PlateId id) => _byId[id]?.record;

  @override
  List<PlateRecord> recentPlates({int limit = 50}) {
    final list = _byId.values.map((s) => s.record).toList();
    list.sort((a, b) => b.lastSeen.compareTo(a.lastSeen)); // desc
    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  @override
  PlateHistoryPage plateHistory(
    PlateId id, {
    int limit = 50,
    int offset = 0,
  }) {
    final slot = _byId[id];
    if (slot == null) {
      return PlateHistoryPage(
        plateId: id,
        events: const [],
        hasMore: false,
      );
    }
    // Events stored natural append order; we want descending by ts.
    final eventsDesc =
        List<RecognitionEvent>.from(slot.events)..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final sliceStart = offset;
    final sliceEnd = (offset + limit) > eventsDesc.length
        ? eventsDesc.length
        : (offset + limit);
    final page = eventsDesc.sublist(sliceStart, sliceEnd);
    final hasMore = sliceEnd < eventsDesc.length;
    return PlateHistoryPage(
      plateId: id,
      events: page,
      hasMore: hasMore,
    );
  }

  @override
  (int plates, int recognitions) stats() {
    int recognitions = 0;
    for (final slot in _byId.values) {
      recognitions += slot.events.length;
    }
    return (_byId.length, recognitions);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _changeCtrl.close();
    _disposed = true;
  }
}

/// Convenience extension for attaching repository to pipeline plans stream.
extension RecognitionPipelinePlanAttach on InMemoryPlateRepository {
  StreamSubscription<PipelineUpsert> attachToPipelinePlans(
    Stream<PipelineUpsert> plans,
  ) {
    return plans.listen((p) {
      applyUpsert(p.plan);
    });
  }
}

/// Debug / developer utilities.
extension InMemoryPlateRepositoryDebug on InMemoryPlateRepository {
  /// Dump current repository summary as a map (for logs/tests).
  Map<String, Object?> snapshotSummary() {
    final (plates, recognitions) = stats();
    return {
      'plates': plates,
      'recognitions': recognitions,
      'recentPlateIds': recentPlates(limit: 5).map((r) => r.id.value).toList(),
    };
  }

  /// Retrieve full event list for a plate (testing aid).
  List<RecognitionEvent> allEventsForPlate(PlateId id) =>
      List.unmodifiable(_byId[id]?.events ?? const []);
}

// End of file.