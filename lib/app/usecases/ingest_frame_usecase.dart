/// Ingest Frame Use Case (Scaffold)
///
/// High-level orchestration for handling a single sampled frame in the
/// recognition pipeline. This wires together *pure* domain transformations
/// with *imperative* repository / adapter boundaries without embedding
/// side-effect logic directly in domain code.
///
/// Responsibilities (MVP scope):
/// 1. Accept a sampled frame descriptor + raw detections from the active model.
/// 2. Normalize plate text & fuse confidence (pure domain helpers).
/// 3. Filter by minimum confidence threshold.
/// 4. Dedupe against recent window (time-based only for MVP).
/// 5. For each surviving detection, build an upsert plan:
///      - Insert new plate + first event OR
///      - Insert event + update existing plate aggregate fields
/// 6. Hand plans to persistence sink (transaction applied downstream).
/// 7. Emit a structured result with counts / accepted events.
///
/// NOT in scope (yet):
/// - Backpressure / sampling policy decisions
/// - Concurrency / isolate management
/// - Geo distance dedupe (time-only now)
/// - Performance instrumentation (placeholder hooks included)
/// - Adapter health state transitions
///
/// All external side effects (DB writes, logging, metrics) happen *outside* or
/// via injected boundary abstractions so this class remains testable.
///
/// See docs:
/// - docs/architecture/pipeline.md
/// - docs/data/domain_model.md
/// - docs/models/model_adapters.md
library ingest_frame_usecase;

import 'package:plate_runner/domain/plate_entities.dart';

/// Lightweight frame descriptor (no pixel buffers retained here).
/// A richer type can be introduced later with size, format, orientation, etc.
class FrameSample {
  final String id; // Correlates with adapter/logging (e.g., monotonic counter)
  final int epochMs; // Capture time
  const FrameSample({required this.id, required this.epochMs});
}

/// Raw model detection prior to normalization/confidence fusion.
/// (Adapter layer would normally define this; kept local until adapter code lands.)
class RawModelDetection {
  final String rawText;
  final double rawConfidence; // 0..1 (adapter interpreted)
  final bool lowLight;
  final bool partial;
  final bool blurred;

  const RawModelDetection({
    required this.rawText,
    required this.rawConfidence,
    this.lowLight = false,
    this.partial = false,
    this.blurred = false,
  });
}

/// Policy / runtime configuration snapshot needed for ingestion.
/// Additional tunables (sampling interval, dedupe mode) can be added later.
class IngestPolicy {
  final double minFusedConfidence;
  final Duration dedupeWindow;
  const IngestPolicy({
    required this.minFusedConfidence,
    required this.dedupeWindow,
  });
}

/// Repository boundary for plate aggregate lookups.
abstract interface class PlateQueryRepository {
  /// Retrieve current aggregate by normalized plate (or null if not found).
  Future<PlateRecord?> fetchByNormalized(NormalizedPlate plate);
}

/// Persistence sink boundary applying a batch of upsert plans atomically.
/// Implementation decides transaction semantics.
abstract interface class UpsertPlanApplier {
  Future<void> applyPlans(List<UpsertPlan> plans);
}

/// Cache / window provider for recent events to support dedupe.
/// Implementation might keep a rolling in-memory window keyed by plate.
abstract interface class RecentEventsWindow {
  /// Return events currently inside the dedupe window (time-bounded) for a plate.
  List<RecognitionEvent> eventsForPlate(NormalizedPlate plate);

  /// Add accepted events (used so subsequent calls can consider them).
  void addEvents(List<RecognitionEvent> events);
}

/// ID provider so domain logic never generates IDs itself.
typedef PlateIdProvider = PlateId Function();

/// Clock abstraction (epoch ms) to avoid direct DateTime.now() in tests.
typedef EpochMsNow = int Function();

/// Ingest request containing one frame and its raw detections.
class IngestFrameRequest {
  final FrameSample frame;
  final List<RawModelDetection> rawDetections;
  final IngestPolicy policy;
  const IngestFrameRequest({
    required this.frame,
    required this.rawDetections,
    required this.policy,
  });
}

/// Outcome representation after ingestion orchestration.
class IngestFrameResult {
  final FrameSample frame;
  final List<RecognitionEvent> acceptedEvents;
  final List<RawModelDetection> rejectedLowConfidence;
  final int dedupSkipped;
  final List<UpsertPlan> plans; // For observability / testing

  const IngestFrameResult({
    required this.frame,
    required this.acceptedEvents,
    required this.rejectedLowConfidence,
    required this.dedupSkipped,
    required this.plans,
  });

  @override
  String toString() =>
      'IngestFrameResult(frame=${frame.id}, accepted=${acceptedEvents.length}, '
      'lowConf=${rejectedLowConfidence.length}, dedupSkipped=$dedupSkipped, plans=${plans.length})';
}

/// Use case orchestrator.
/// Keep this class stateless; all mutable state flows through injected collaborators.
final class IngestFrameUseCase {
  final PlateQueryRepository plateRepo;
  final UpsertPlanApplier planApplier;
  final RecentEventsWindow recentWindow;
  final PlateIdProvider newPlateId;
  final EpochMsNow nowEpochMs;

  const IngestFrameUseCase({
    required this.plateRepo,
    required this.planApplier,
    required this.recentWindow,
    required this.newPlateId,
    required this.nowEpochMs,
  });

  /// Execute ingestion for a single frame.
  ///
  /// Steps:
  /// - Normalize + fuse confidence
  /// - Threshold filter
  /// - Dedupe
  /// - Build upsert plans
  /// - Apply plans
  Future<IngestFrameResult> execute(IngestFrameRequest req) async {
    // 1. Normalize & fuse
    final normalized = <({
      RawModelDetection raw,
      NormalizedPlate? plate,
      ConfidenceScore? fused
    })>[];

    for (final raw in req.rawDetections) {
      final normRes = normalizePlate(raw.rawText);
      if (normRes is Failure<NormalizedPlate, DomainError>) {
        // Skip invalid plate formats silently (could log via hook later).
        continue;
      }
      final fusedRes = fuseConfidence(ConfidenceFusionContext(
        rawScore: raw.rawConfidence,
        lowLight: raw.lowLight,
        partial: raw.partial,
        blurred: raw.blurred,
      ));
      if (fusedRes is Failure<ConfidenceScore, DomainError>) {
        // Out-of-range confidence treated as invalid detection; skip.
        continue;
      }
      normalized.add((
        raw: raw,
        plate: (normRes as Success<NormalizedPlate, DomainError>).value,
        fused: (fusedRes as Success<ConfidenceScore, DomainError>).value
      ));
    }

    // 2. Threshold filter
    final thresholded = normalized.where((n) {
      final score = n.fused!;
      return score.value >= req.policy.minFusedConfidence;
    }).toList();

    final rejectedLowConfidence = normalized
        .where((n) =>
            n.fused != null && n.fused!.value < req.policy.minFusedConfidence)
        .map((n) => n.raw)
        .toList();

    if (thresholded.isEmpty) {
      return IngestFrameResult(
        frame: req.frame,
        acceptedEvents: const [],
        rejectedLowConfidence: rejectedLowConfidence,
        dedupSkipped: 0,
        plans: const [],
      );
    }

    // 3. Dedupe (time-only). We create candidate events first with placeholder PlateIds.
    final now = nowEpochMs();
    final candidateEvents = <RecognitionEvent>[];
    for (final t in thresholded) {
      final plate = t.plate!;
      // Pre-check recent window for dedupe BEFORE generating event.
      final recentForPlate = recentWindow.eventsForPlate(plate);
      final duplicate = recentForPlate.any((e) =>
          (now - e.timestamp).abs() <= req.policy.dedupeWindow.inMilliseconds);
      if (duplicate) {
        continue;
      }
      final event = RecognitionEvent(
        plateId: PlateId.fromString(
            '_TEMP'), // Placeholder; will be replaced in plan if new.
        plate: plate,
        confidence: t.fused!,
        timestamp: now,
      );
      candidateEvents.add(event);
    }

    final dedupSkipped =
        thresholded.length - candidateEvents.length; // number filtered out

    if (candidateEvents.isEmpty) {
      return IngestFrameResult(
        frame: req.frame,
        acceptedEvents: const [],
        rejectedLowConfidence: rejectedLowConfidence,
        dedupSkipped: dedupSkipped,
        plans: const [],
      );
    }

    // 4. Build upsert plans (needs existing plate aggregates)
    final plans = <UpsertPlan>[];
    final acceptedEvents = <RecognitionEvent>[];

    for (final event in candidateEvents) {
      final existing = await plateRepo.fetchByNormalized(event.plate);
      final plan = buildUpsertPlan(
        existing: existing,
        event: event,
        newPlateIdProvider: newPlateId,
      );
      plans.add(plan);
      switch (plan) {
        case InsertNewPlateAndEvent(:final event):
          acceptedEvents.add(event);
        case InsertEventAndUpdatePlate(:final event):
          acceptedEvents.add(event);
      }
    }

    // 5. Apply plans (atomic persistence handled by adapter)
    if (plans.isNotEmpty) {
      await planApplier.applyPlans(plans);
      // Update dedupe window *after* persistence succeeds.
      recentWindow.addEvents(acceptedEvents);
    }

    // 6. Return detailed result
    return IngestFrameResult(
      frame: req.frame,
      acceptedEvents: acceptedEvents,
      rejectedLowConfidence: rejectedLowConfidence,
      dedupSkipped: dedupSkipped,
      plans: plans,
    );
  }
}

/// Future enhancements (notes):
/// - Add instrumentation hooks (latency spans, counters)
/// - Support batching multiple frames
/// - Introduce geo-based dedupe (extend RecentEventsWindow API)
/// - Plug adapter health feedback if repeated failures occur
/// - Integrate configuration reloading (policy updates mid-session)