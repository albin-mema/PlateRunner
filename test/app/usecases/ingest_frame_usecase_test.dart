import 'package:flutter_test/flutter_test.dart';

import 'package:plate_runner/app/usecases/ingest_frame_usecase.dart'
    as uc; // alias to avoid name clashes
import 'package:plate_runner/app/usecases/ingest_frame_usecase.dart';
import 'package:plate_runner/domain/plate_entities.dart';
import 'package:plate_runner/infrastructure/db/in_memory_ingest_store.dart';
import 'package:plate_runner/infrastructure/model/model_adapter.dart';

/// Test strategy:
///  - Exercise the ingest orchestration end-to-end using the in-memory store.
///  - Use the deterministic mock adapter to produce pseudo-random but stable
///    raw detections from frame ids.
///  - Verify:
///      * Normalization + confidence thresholding
///      * Deduplication window behavior
///      * Upsert plan generation (new vs existing plate)
///      * Handling of invalid plate formats & low-confidence filtering
///
/// Notes:
///  - The ingest use case treats raw model detections as opaque simple structs;
///    we bridge adapter RawPlateDetection → use case RawModelDetection manually.
///  - Time & ID sources are injected to ensure deterministic expectations.
///  - Because the mock adapter can return 0 detections for some frame ids,
///    a helper acquires a non-empty detection set for robust assertions.
void main() {
  group('IngestFrameUseCase', () {
    late InMemoryIngestStore store;
    late IngestFrameUseCase ingest;
    late DeterministicMockAdapter adapter;

    // Deterministic (mutable) clock
    int currentEpochMs = 1000000;
    int nowEpochMs() => currentEpochMs;

    // Simple incremental plate id provider
    int _idCounter = 0;
    PlateId nextPlateId() => PlateId.fromString('P${_idCounter++}');

    uc.IngestPolicy defaultPolicy() => const uc.IngestPolicy(
          minFusedConfidence: 0.55,
          dedupeWindow: Duration(seconds: 3),
        );

    setUp(() {
      store = InMemoryIngestStore(maxRecentEventsPerPlate: 16);
      adapter = DeterministicMockAdapter(
        seed: 99,
        simulatedLatencyMs: 1, // keep tests fast
        maxPlatesPerFrame: 2,
      );
      ingest = IngestFrameUseCase(
        plateRepo: store,
        planApplier: store,
        recentWindow: store,
        newPlateId: nextPlateId,
        nowEpochMs: nowEpochMs,
      );
      _idCounter = 0;
      currentEpochMs = 1000000;
    });

    Future<List<RawPlateDetection>> _adapterDetectionsNonEmpty() async {
      var attempt = 0;
      while (attempt < 10) {
        final frameId = 'frame_$attempt';
        final frame = FrameDescriptor(
          id: frameId,
          epochMs: nowEpochMs(),
          width: 320,
          height: 192,
          format: FramePixelFormat.yuv420,
        );
        final list = await adapter.detect(frame);
        if (list.isNotEmpty) return list;
        attempt++;
      }
      return const [];
    }

    List<uc.RawModelDetection> _bridge(
      List<RawPlateDetection> rawList,
    ) {
      return rawList
          .map((r) => uc.RawModelDetection(
                rawText: r.rawText,
                rawConfidence: r.confidenceRaw,
                // Map adapter qualityFlags heuristically into booleans.
                lowLight: QualityFlag.has(r.qualityFlags, QualityFlag.lowLight),
                partial: QualityFlag.has(r.qualityFlags, QualityFlag.partial),
                blurred: QualityFlag.has(r.qualityFlags, QualityFlag.blur),
              ))
          .toList();
    }

    test('ingest first frame persists new plates & events', () async {
      final detections = await _adapterDetectionsNonEmpty();
      expect(detections, isNotEmpty,
          reason: 'Mock adapter produced no detections after retries');

      final bridged = _bridge(detections);

      final req = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'f1', epochMs: nowEpochMs()),
        rawDetections: bridged,
        policy: defaultPolicy(),
      );

      final result = await ingest.execute(req);

      // All accepted events should correspond 1:1 with plans.
      expect(result.acceptedEvents.length, equals(result.plans.length));

      // Ensure normalization produced valid pattern.
      for (final ev in result.acceptedEvents) {
        expect(RegExp(r'^[A-Z0-9\-]{2,16}$').hasMatch(ev.plate.value), isTrue);
      }

      // We persisted plates & events via store; snapshot should reflect.
      final snapshot = store.debugSnapshot();
      final plateCount = snapshot['plates'] as int;
      final eventsTotal = snapshot['eventsTotal'] as int;

      // Because each accepted event for a new plate generates an InsertNew or InsertEvent,
      // verify counts align (some events could share the same plate if duplicates suppressed).
      expect(eventsTotal, equals(result.acceptedEvents.length));
      // Distinct normalized plates should equal count of unique event.plates
      final distinctPlates =
          result.acceptedEvents.map((e) => e.plate.value).toSet().length;
      expect(plateCount, equals(distinctPlates));
    });

    test(
        'second ingest within dedupe window skips duplicates (dedupSkipped > 0)',
        () async {
      final detections = await _adapterDetectionsNonEmpty();
      final bridged = _bridge(detections);

      // First ingest
      final firstReq = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'fA', epochMs: nowEpochMs()),
        rawDetections: bridged,
        policy: defaultPolicy(),
      );
      final firstResult = await ingest.execute(firstReq);
      final acceptedFirst = firstResult.acceptedEvents.length;
      expect(acceptedFirst, greaterThanOrEqualTo(1),
          reason: 'Need at least 1 accepted event to test dedupe');

      // Without advancing clock beyond dedupe window
      currentEpochMs += 500; // 0.5s later (within 3s window)

      final secondReq = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'fB', epochMs: nowEpochMs()),
        rawDetections: bridged,
        policy: defaultPolicy(),
      );
      final secondResult = await ingest.execute(secondReq);

      // All would be considered duplicates (or at least some) → some skipped
      expect(secondResult.dedupSkipped, greaterThanOrEqualTo(1));
      expect(secondResult.acceptedEvents.length,
          lessThanOrEqualTo(acceptedFirst));
    });

    test(
        'ingest outside dedupe window accepts new events for existing plates (updates aggregate)',
        () async {
      final detections = await _adapterDetectionsNonEmpty();
      final bridged = _bridge(detections);

      // First ingest
      final firstReq = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'f1', epochMs: nowEpochMs()),
        rawDetections: bridged,
        policy: defaultPolicy(),
      );
      final firstResult = await ingest.execute(firstReq);
      final acceptedFirst = firstResult.acceptedEvents.length;
      expect(acceptedFirst, greaterThanOrEqualTo(1));

      // Advance clock beyond 3s dedupe window
      currentEpochMs += 4000;

      final secondReq = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'f2', epochMs: nowEpochMs()),
        rawDetections: bridged,
        policy: defaultPolicy(),
      );
      final secondResult = await ingest.execute(secondReq);

      // Expect events accepted again (same plates but outside window)
      expect(secondResult.acceptedEvents.length, equals(acceptedFirst));

      // Verify aggregate updated (totalRecognitions incremented).
      final plates = store.debugAllPlates();
      for (final p in plates) {
        // Each plate should have at least 2 recognitions now.
        expect(p.totalRecognitions, greaterThanOrEqualTo(2));
      }
    });

    test(
        'invalid plate formats skipped; low-confidence filtered; only valid accepted',
        () async {
      // Craft raw detections manually (bypass adapter)
      final raw = <uc.RawModelDetection>[
        uc.RawModelDetection(
          rawText: '@@@', // invalid after normalization
          rawConfidence: 0.95,
        ),
        uc.RawModelDetection(
          rawText: 'VALID1',
          rawConfidence: 0.20, // below threshold
        ),
        uc.RawModelDetection(
          rawText: 'GOOD99',
          rawConfidence: 0.90, // should pass
        ),
      ];

      final policy = const uc.IngestPolicy(
        minFusedConfidence: 0.6,
        dedupeWindow: Duration(seconds: 3),
      );

      final req = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'f_custom', epochMs: nowEpochMs()),
        rawDetections: raw,
        policy: policy,
      );

      final result = await ingest.execute(req);

      expect(result.acceptedEvents.length, equals(1),
          reason: 'Only one detection should survive filters');
      expect(result.rejectedLowConfidence.length, equals(1),
          reason: 'One low-confidence detection should be reported');
      expect(result.dedupSkipped, equals(0));
      expect(result.plans.length, equals(1));

      final plateValue = result.acceptedEvents.single.plate.value;
      expect(plateValue, equals('GOOD99'));
    });

    test('no detections -> empty result and no persistence side-effects',
        () async {
      final req = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'empty_frame', epochMs: nowEpochMs()),
        rawDetections: const [], // nothing
        policy: defaultPolicy(),
      );
      final result = await ingest.execute(req);
      expect(result.acceptedEvents, isEmpty);
      expect(result.plans, isEmpty);
      expect(store.debugSnapshot()['plates'], equals(0));
      expect(store.debugSnapshot()['eventsTotal'], equals(0));
    });

    test('confidence penalties (blur/partial/lowLight) reduce fused score',
        () async {
      // Build a detection that just hovers around threshold before penalties
      final policy = const uc.IngestPolicy(
        minFusedConfidence: 0.70,
        dedupeWindow: Duration(seconds: 3),
      );

      // Raw 0.78 with penalties (partial 0.10, blurred 0.08, lowLight 0.05) => 0.55 < 0.70
      final penalized = uc.RawModelDetection(
        rawText: 'PLT777',
        rawConfidence: 0.78,
        partial: true,
        blurred: true,
        lowLight: true,
      );

      final good = uc.RawModelDetection(
        rawText: 'OK999',
        rawConfidence: 0.90,
      );

      final req = uc.IngestFrameRequest(
        frame: uc.FrameSample(id: 'penalty_frame', epochMs: nowEpochMs()),
        rawDetections: [penalized, good],
        policy: policy,
      );

      final result = await ingest.execute(req);

      expect(result.acceptedEvents.length, equals(1));
      expect(result.rejectedLowConfidence.length, equals(1));
      final acceptedPlate = result.acceptedEvents.single.plate.value;
      expect(acceptedPlate, equals('OK999'));
    });
  });
}