# Feature TODO: Recognition Pipeline Implementation

Status: Draft (v0.1)  
Owner: (assign)  
Related Docs: ../architecture/pipeline.md • ../architecture/overview.md • ../data/domain_model.md • ../dev/performance.md • runtime_config_persistence.md  
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

---

## 1. Goal

Implement the end‑to‑end recognition pipeline that ingests camera frames, performs model inference, normalizes & fuses detections, deduplicates events, persists recognition results, and emits reactive UI/state updates — adhering to the "functional core / imperative shell" architecture and performance targets.

---

## 2. In-Scope (MVP)

- Single active model adapter (no multi-model voting).
- Time‑based dedup window (no geo sensitivity yet).
- Adaptive (fixed interval first, motion-aware hook stub).
- Persistence via repository interface (SQLite stub or in‑memory placeholder).
- Structured logging (console; future: pluggable sink).
- Simple state emission (stream or notifier) for recent recognitions / plate history.
- Degradation heuristic (latency + timeout counters) toggling a few config-driven behaviors.

---

## 3. Out of Scope (MVP)

- Geo distance deduplication.
- Parallel / batched inference.
- Watchlist / alert rules.
- On‑device model hot switching beyond `activeModelId` field swap.
- Full dev overlay UI (only hook events / simple counters).
- Encryption or remote telemetry export.
- Power / thermal integration.

---

## 4. Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| PIPE-01 | Accept frame descriptors from camera capture source | Must |
| PIPE-02 | Decide sampling (should process or skip) | Must |
| PIPE-03 | Pass selected frames to model adapter with timeout | Must |
| PIPE-04 | Normalize & fuse raw detections deterministically | Must |
| PIPE-05 | Discard detections below min fused confidence | Must |
| PIPE-06 | Deduplicate within rolling time window | Must |
| PIPE-07 | Build immutable upsert plan for persistence | Must |
| PIPE-08 | Apply plan atomically (transaction abstraction) | Must |
| PIPE-09 | Emit recognition state updates | Must |
| PIPE-10 | Track metrics (latency, events, skips, degrade flags) | Must |
| PIPE-11 | Trigger degraded mode & recover | Should |
| PIPE-12 | Provide test seam for deterministic adapter | Must |
| PIPE-13 | Provide structured logs for key events | Must |
| PIPE-14 | Graceful shutdown disposal (cancel loops, flush) | Must |
| PIPE-15 | Support runtime config updates (reactive) | Should |

---

## 5. Non-Functional Requirements

| Category | Target |
|----------|--------|
| Inference p95 | < 120 ms (baseline) |
| End-to-end median (capture → persisted) | < 150 ms |
| Memory overhead (buffers + adapter) | < 90 MB |
| Dropped frame ratio | < 40% by design |
| Code test coverage (pure functions) | ≥ 85% |
| Deterministic test mode | Same input -> same output hash |

---

## 6. Core Data Contracts (Implementation Alignment)

Already sketched in architecture doc; implement as immutable value classes (pure Dart):

- `Frame`
- `RawPlateDetection`
- `NormalizedDetection`
- `UpsertPlan`
- `RecognitionEvent`
- `PlateSnapshot`
- `PipelineMetricsSnapshot` (rolling summary for UI/overlay)

Location: `lib/domain/pipeline/` (pure) except DTOs reused by infra may live in `domain/model/`.

---

## 7. Proposed Directory Layout (New / Expanded)

```
lib/
  domain/
    pipeline/
      sampling/
        sampling_strategy.dart
        fixed_interval_strategy.dart
        motion_adaptive_strategy.dart (stub)
      dedup/
        dedup_strategy.dart
        time_window_dedup.dart
      fusion/
        confidence_fusion.dart
        ambiguity_table.dart
      planning/
        upsert_plan_builder.dart
      model/
        frame.dart
        raw_detection.dart
        normalized_detection.dart
        quality_flags.dart
        pipeline_metrics.dart
      pipeline_core.dart        (pure orchestration funcs)
  infrastructure/
    camera/
      camera_frame_source.dart  (stream provider stub)
    model/
      model_adapter.dart
      tflite_model_adapter.dart (placeholder stub)
    persistence/
      plate_repository.dart
      recognition_repository.dart
      pipeline_txn_executor.dart
      in_memory_repos.dart (MVP stub)
    logging/
      structured_logger.dart
    metrics/
      metrics_collector.dart
  app/
    usecases/
      start_pipeline.dart
      stop_pipeline.dart
      observe_recent_recognitions.dart
      update_runtime_config_listener.dart
  features/
    recognition/
      controllers/
        recognition_stream_controller.dart
      widgets/ (future)
```

---

## 8. High-Level Flow (Concrete MVP)

1. Camera emits `Frame`.
2. `SamplingStrategy.shouldProcess(lastState, frame)` -> bool.
3. If skip: record skip reason, update counters, continue.
4. Submit frame to inference worker queue (bounded length 1–2).
5. Worker takes frame, times `ModelAdapter.detect(frame)`.
6. For each raw detection:
   - Normalize text (region rules placeholder).
   - Apply fusion penalties (ambiguity + quality flags).
   - Filter by `config.minFusedConfidence`.
7. Deduplicate vs time window buffer.
8. For each accepted detection:
   - Build `UpsertPlan` using existing plate snapshot (cache / repo).
   - Execute plan transactionally.
   - Update caches / metrics.
   - Emit recognition event to observers.
9. Prune dedup window.
10. Update metrics (latency histograms, counts).
11. Evaluate degradation / recovery conditions; possibly adjust runtime config (through service).
12. Loop.

---

## 9. Core Interfaces (Initial Signatures)

(Pure domain — no Flutter dependencies.)

```
abstract interface class SamplingStrategy {
  bool shouldProcess(PipelineSamplingState state, Frame frame, RuntimeConfig cfg, int nowMs);
}

abstract interface class ModelAdapter {
  String get modelId;
  Future<List<RawPlateDetection>> detect(Frame frame, {Duration? timeout});
  Future<void> warmup();
  Future<void> dispose();
}

typedef PlateKey = String;

abstract interface class PlateRepository {
  Future<PlateSnapshot?> findPlate(PlateKey key);
  Future<PlateSnapshot> insertPlate(PlateData data);
  Future<void> updatePlate(PlateUpdatePatch patch);
}

abstract interface class RecognitionRepository {
  Future<RecognitionEvent> insertEvent(RecognitionEventData data);
}

abstract interface class PipelineTransactionExecutor {
  Future<T> run<T>(Future<T> Function() body);
}

abstract interface class StructuredLogger {
  void log(String component, String event, Map<String, Object?> fields);
}

abstract interface class MetricsCollector {
  void recordInferenceLatency(int ms);
  void recordFrameSkipped(String reason);
  void recordRecognition(double confidence);
  void recordTimeout();
  PipelineMetricsSnapshot snapshot();
}
```

Pure functions:

- `NormalizedDetection normalizeAndFuse(RawPlateDetection raw, FusionConfig cfg)`
- `List<NormalizedDetection> dedupeDetections(List<NormalizedDetection> window, List<NormalizedDetection> incoming, DedupConfig cfg, int nowMs)`
- `UpsertPlan buildUpsertPlan(PlateSnapshot? existing, NormalizedDetection d, int nowMs)`
- `PlateStats computePlateStats(List<RecognitionEvent> recent)`

---

## 10. Configuration Mapping

RuntimeConfig fields consumed:

| RuntimeConfig Field | Usage |
|---------------------|-------|
| minFusedConfidence | Filter normalized detections |
| dedupeWindowMs | Prune + dedup logic |
| activeModelId | Model adapter selection |
| samplingIntervalMs | FixedInterval strategy interval |
| modelInferenceTimeoutMs | Timeout on adapter.detect |
| enableCharScores | Whether to request charScores (if model supports) |
| enableVerbosePipelineLogs | Toggle verbose logging |
| allowConcurrentDetect (currently false in MVP) | Gate for concurrency scaling |
| enableDevOverlay | Provide hook to overlay metrics (future) |

---

## 11. Degradation Heuristic (MVP)

Triggers:
- Rolling p95 inference latency > `degradeP95LatencyMs`.
- Consecutive timeouts > `degradeFailureWindow`.

Actions:
- Increase samplingIntervalMs (e.g., +50% bounded).
- Disable `enableCharScores` (if toggled on).
- Emit `pipeline_degraded`.

Recovery:
- p95 below threshold for N windows (e.g., 3) → restore baseline; emit `pipeline_recovered`.

Implement evaluation in periodic tick (every M frames or every K ms).

---

## 12. Concurrency & State

- Single isolate.
- One inference worker (queue length 1–2).
- Dedup window: simple in-memory list (time-sorted) of `NormalizedDetectionWindowEntry`.
- Plate cache: LRU map keyed by `PlateKey` (size configurable future).
- All shared structures mutated inside pipeline loop (no explicit locking needed if loop serialized).

---

## 13. Error Handling Strategy

| Failure | Handling |
|---------|----------|
| Model timeout | Cancel future, record timeout, skip frame |
| Model exception | Log event `inference_error`, maybe attempt warmup retry count-limited |
| Persistence failure | Abort txn, log `persistence_error`, optionally increment failure metric |
| Normalization exception (should not) | Catch + discard detection, log once per signature |
| Memory pressure (not implemented) | Placeholder hook |

No unhandled exceptions should escape the pipeline loop; loop resiliency > crash.

---

## 14. Logging Events (Structured)

Component `pipeline` events:
- `frame_skipped` { reason }
- `inference_start` { frameId }
- `inference_complete` { frameId, latencyMs, detectionCount }
- `inference_timeout`
- `inference_error` { error }
- `dedupe_suppressed` { key, prevTsDeltaMs }
- `recognition_persisted` { plate, confidence, inferenceMs }
- `pipeline_degraded`
- `pipeline_recovered`

Component `config` (reuse from persistence doc) for dynamic adjustments.

---

## 15. Metrics (MVP Implementation)

Collected (in-memory):
- `inferenceLatencySamples` (ring buffer / histogram)
- counters: framesOffered, framesProcessed, framesSkippedByReason
- totalDetectionsRaw, totalDetectionsAccepted
- recognizedEventsPersisted
- timeouts, errors
- currentState (NORMAL|DEGRADED)

Expose `PipelineMetricsSnapshot` immutable for UI.

---

## 16. Testing Strategy

Pure Unit:
- Fusion penalties & ambiguity logic determinism.
- Dedup window acceptance / suppression cases (boundary times).
- Upsert plan builder with plate exists vs not exists.
- Sampling strategy decisions for intervals.

Contract Tests:
- Fake adapter producing scripted raw detections → expected persisted events sequence.
- Timeout simulation.

Load / Stress:
- Synthetic 10k frame loop with randomized detection densities; assert memory stable & p95 latency within bound (mock inference timing).

Determinism:
- Fixed clock + deterministic adapter mapping frameId -> raw detections => hash of persisted recognition keys stable.

Failure Injection:
- Adapter throws intermittent.
- Transaction executor throws.

---

## 17. Implementation Phases

Phase 1 (Scaffolding):
1. Create domain model classes & interfaces.
2. Implement fixed interval sampling.
3. Implement normalization + fusion (ambiguity + clamp).
4. Implement time-window dedup (simple list prune).
5. Implement upsert plan builder (in-memory repo stub).
6. Wire pipeline loop (single worker) with fake adapter + in-memory repos.
7. Basic logging + metrics snapshot.

Phase 2 (Hardening):
8. Add timeout logic to model adapter invocation.
9. Add degradation heuristic evaluation & config adjustments (via service.update()).
10. Add structured logger abstraction + simple console implementation.
11. Add plate cache + stats patch updates.

Phase 3 (Optimization / Extension):
12. Add motion adaptive sampling stub integration.
13. Add char score optional integration path (flag).
14. Add metrics histogram structure (p50/p95 extraction).
15. Integrate runtime config persistence; early bootstrap.

Phase 4 (Polish):
16. Add unit + contract tests, finalize coverage.
17. Add pipeline disposal (cancels timers, closes streams).
18. Add graceful restart API (stop + start preserving caches).
19. Document public interfaces & invariants.

---

## 18. Open Questions

| ID | Question | Status |
|----|----------|--------|
| PIPE-PQ-01 | Should sampling strategy selection be dynamic (config flag)? | Likely yes (later) |
| PIPE-PQ-02 | Introduce metrics isolate or keep inline? | Defer |
| PIPE-PQ-03 | Are ambiguous char penalties linear or table-driven per char? | Start linear per ambiguous occurrence |
| PIPE-PQ-04 | Use monotonic clock vs DateTime.now()? | Use monotonic if available (performance) |
| PIPE-PQ-05 | Plate stats aggregation incremental vs recompute? | Incremental patch (MVP) |
| PIPE-PQ-06 | Provide external backpressure to camera stream? | Not MVP |

---

## 19. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Latency spikes from synchronous logging | Drops FPS | Batch / minimal logs in prod mode flag |
| Memory growth in dedup window | OOM risk | Aggressive prune each loop based on nowMs |
| Adapter warmup delay blocking UI | Perceived lag | Warmup async prior to enabling pipeline processing |
| Config updates mid-flight cause state races | Inconsistent decisions | Snapshot config at each loop iteration |
| Over-tight sampling interval saturates CPU | Battery drain | Enforce minimum clamp (e.g., >= 16ms) |

---

## 20. Definition of Done (MVP)

- Pipeline processes frames → persisted recognition events with correct dedup behavior.
- All pure functions covered by tests, contract test passes deterministic scenario.
- Structured logs appear for each major event (verified).
- Metrics snapshot includes latency p95, processed vs skipped counts.
- Degraded mode triggers under injected timeout load and recovers after stabilizing.
- No unhandled exceptions during 5k synthetic frame run test.
- Code documented (inline) and this file updated with final version.

---

## 21. Future Extensions

- Geo-assisted dedup (distance threshold).
- Multi-adapter consensus fusion.
- Watchlist / alert rule engine post-dedup pre-persist.
- Real-time overlay UI (FPS, latency bars, last detection).
- Persistent metrics ring buffer or export for diagnostics.
- GPU / NNAPI delegate selection logic (adapter capability negotiation).
- Adaptive confidence threshold tuning (calibration curve) once dataset collected.

---

## 22. Example Orchestration Skeleton (Conceptual)

```dart
class RecognitionPipeline {
  final SamplingStrategy sampler;
  final ModelAdapter adapter;
  final PlateRepository plateRepo;
  final RecognitionRepository recognitionRepo;
  final PipelineTransactionExecutor txn;
  final StructuredLogger log;
  final MetricsCollector metrics;
  final InMemoryRuntimeConfigService configService;

  final _dedupWindow = <NormalizedDetection>[];
  bool _running = false;

  Future<void> start(Stream<Frame> frames) async {
    _running = true;
    await adapter.warmup();
    frames.listen(_onFrame, onDone: stop, onError: _onError);
  }

  Future<void> _onFrame(Frame f) async {
    if (!_running) return;
    final cfg = configService.current; // snapshot
    final now = _nowMs();
    if (!sampler.shouldProcess(/*state*/ PipelineSamplingState(), f, cfg, now)) {
      metrics.recordFrameSkipped('SAMPLING');
      return;
    }
    final t0 = now;
    List<RawPlateDetection> raws;
    try {
      raws = await adapter
          .detect(f, timeout: Duration(milliseconds: cfg.modelInferenceTimeoutMs));
    } catch (e) {
      metrics.recordTimeout();
      log.log('pipeline', 'inference_error', {'error': e.toString()});
      return;
    }
    final norm = raws
        .map((r) => normalizeAndFuse(r, _fusionConfigFrom(cfg)))
        .where((d) => d.fusedConfidence >= cfg.minFusedConfidence)
        .toList();

    final accepted = dedupeDetections(_dedupWindow, norm,
        DedupConfig(windowMs: cfg.dedupeWindowMs), now);

    for (final d in accepted) {
      final existing = await plateRepo.findPlate(d.plateKey);
      final plan = buildUpsertPlan(existing, d, now);
      await txn.run(() async {
        final plate = existing ?? await plateRepo.insertPlate(plan.plate.create!);
        await recognitionRepo.insertEvent(plan.recognition);
        // apply plate update patch if any...
      });
      metrics.recordRecognition(d.fusedConfidence);
      log.log('pipeline', 'recognition_persisted', {
        'plate': d.normalizedText,
        'confidence': d.fusedConfidence,
      });
    }
    _pruneDedup(_dedupWindow, now, cfg.dedupeWindowMs);
    metrics.recordInferenceLatency(_nowMs() - t0);
  }

  Future<void> stop() async {
    _running = false;
    await adapter.dispose();
  }
}
```

(Actual implementation will separate concerns further; code above is illustrative only.)

---

## 23. Task Checklist (Actionable)

- [ ] Add domain model classes.
- [ ] Implement fusion penalties + ambiguity table.
- [ ] Implement dedup strategy (time window).
- [ ] Implement upsert plan builder.
- [ ] Create sampling strategies (fixed + motion stub).
- [ ] Define repositories + in-memory stubs.
- [ ] Define model adapter interface + fake adapter (configurable latency).
- [ ] Implement metrics collector (histogram calc).
- [ ] Implement structured logger (console).
- [ ] Write recognition pipeline orchestrator (loop).
- [ ] Integrate runtime config service snapshot usage.
- [ ] Add degradation evaluator helper.
- [ ] Add tests: fusion, dedup, sampling, plan builder, end-to-end contract.
- [ ] Add synthetic load test harness (dev).
- [ ] Update README / docs link from overview.
- [ ] Update this file with version bump & mark decisions resolved.

---

## 24. Change Log

| Version | Notes |
|---------|-------|
| 0.1 | Initial draft of implementation plan |

---

End of document.