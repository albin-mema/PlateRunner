# Recognition Pipeline (Short)

Links: [[overview|Architecture]] • [[../data/domain_model|Domain Model]] • [[../data/persistence|Persistence]] • [[../models/model_adapters|Model Adapters]] • [[../dev/testing_strategy|Testing]] • [[../dev/performance|Performance]] • [[../features/todo/README|Feature TODOs]]
Backlinks: [[main|Index]] • [[overview|Architecture]] • [[../dev/performance|Performance]]


## Core Flow
Camera → Sample → Adapter.detect → Normalize + Fuse → Dedup Window → Upsert (SQLite) → Emit State → UI

## Stage Summary
| Stage | Pure? | Output | Notes |
|-------|-------|--------|-------|
| Sample | Y | Frame? | Adaptive interval |
| Detect | N | RawDetections | Single in‑flight (MVP) |
| Normalize/Fuse | Y | NormalizedDetections | Region + penalties |
| Dedup | Y | Filtered events | Time window (~3s) |
| Upsert Plan | Y | Plan struct | No side effects |
| Persist | N | DB rows | One transaction |
| Emit | N | UI models | Throttled updates |

## Data (Minimal)
RawPlateDetection(rawText, confidenceRaw, bbox, inferenceTimeMs, qualityFlags)  
NormalizedDetection(plateKey, fusedConfidence, bbox, flags)  
UpsertPlan(plateCreate?, plateUpdate?, recognitionInsert)

## Dedup Window
- Time-only baseline (≈3000 ms)
- Future: optional geo delta
- Replace event only if confidence improves ≥ delta cfg

## Confidence Fusion
fused = raw - (blur + glare + ambiguity penalties) → clamp 0..1  
Ambiguous chars: O/0, B/8, S/5, I/1, G/6

## Performance Levers
Adaptive sampling, window pruning, buffer reuse, short DB txns. Targets in [[../dev/performance|Performance]].

## Degradation (Heuristic)
Trigger: p95 inference > threshold OR timeout ratio high → increase sampling interval & disable optional heuristics → recover when metrics stable.

## Observability
Log tags: [PIPELINE], [DEDUPE], [INFER]. Key counters: processed_fps, inference_ms_p95, dedupe_ratio, txn_ms_p95.

## Pseudocode (Condensed)
```
if shouldSample(frame):
  raws = adapter.detect(frame)
  norm = raws.map(normalize+fuse).filter(c>=cfg.min)
  deduped = dedupe(window, norm)
  for d in deduped:
     plan = buildPlan(repo.find(d.key), d)
     repo.apply(plan)
     emit(d.key)
  prune(window)
```

## Open Questions
Time+geo default? | Confidence calibration timing? | State mgmt integration point? | GPU/NNAPI when?

## Change Log
0.2 Short form replacement (Obsidian links)

---

## 2. High-Level Flow

Textual sequence:

```
Camera Stream
  → Frame Acquisition
    → Frame Sampler (throttle / adaptive skip)
       → Preprocess (resize / color convert)
         → Model Adapter Inference
           → Raw Detections
             → Normalization & Confidence Fusion
               → Deduplication / Clustering Window
                 → Upsert Planning (pure)
                   → Persistence Transaction
                     → State Emission (UI / Subscribers)
```

---

## 3. Pipeline Stages (Detailed)

| Stage | Responsibility | Pure? | Key Output | Notes |
|-------|----------------|-------|------------|-------|
| Frame Acquisition | Acquire raw frames from camera plugin | No (IO) | `Frame` | Ensures orientation metadata |
| Frame Sampler | Decide if frame processed now | Yes (shouldSampleFrame) | bool | Uses motion heuristics + min interval |
| Preprocess | Prepare tensor input | Mixed (transform + buffer mgmt) | Preprocessed buffer | Target zero-copy where possible |
| Inference | Run selected ModelAdapter | No (adapter runtime) | Raw detections | Timeout / latency measured |
| Normalization | Normalize raw plate text | Yes | Normalized candidate(s) | Region strategies optional |
| Confidence Fusion | Adjust raw scores | Yes | Fused confidence | Penalize ambiguity / quality flags |
| Deduplication | Collapse near-duplicates | Yes | Filtered events | Time/geospatial window |
| Upsert Planning | Build DB mutation plan(s) | Yes | Upsert ops struct | No side-effects yet |
| Persistence | Apply transaction | No (DB IO) | Updated plate + event ids | Must be atomic |
| Emission | Notify observers/UI | No (side-effect) | State updates | Fan-out via state mgmt |

---

## 4. Core Data Contracts (Selected)

### 4.1 Frame
```
Frame {
  id: int
  timestampMs: int
  width: int
  height: int
  rotationDeg: int
  format: FrameFormat (yuv420, nv21, etc.)
  pixelRef: native/buffer handle (non-copy)
  motionScore?: double
}
```

### 4.2 RawPlateDetection (from adapter)
```
RawPlateDetection {
  rawText: String
  confidenceRaw: double (0..1)
  bbox: Rect
  inferenceTimeMs: int
  qualityFlags: int bitmask  (BLUR, LOW_LIGHT, PARTIAL, GLARE, MOTION)
  charScores?: List<double>
}
```

### 4.3 NormalizedDetection (post domain normalization)
```
NormalizedDetection {
  plateKey: PlateKey
  normalizedText: String
  fusedConfidence: double
  bbox: Rect
  qualityFlags: int
  source: { modelId, frameId }
  heuristics: { penaltiesApplied: List<String>, base: double }
}
```

### 4.4 UpsertPlan
```
UpsertPlan {
  plate: { create?: PlateData, update?: PlateUpdatePatch }
  recognition: RecognitionEventData
  derivedStats?: PlateStatsPatch
}
```

---

## 5. Functional Core Interfaces

Pure functions (examples):

```
bool shouldSampleFrame(PipelineState s, Frame f);
NormalizedDetection normalizeAndFuse(RawPlateDetection r, RegionRules? rules, FusionConfig cfg);
List<NormalizedDetection> dedupeDetections(List<NormalizedDetection> existingWindow, List<NormalizedDetection> incoming, DedupConfig cfg);
UpsertPlan buildUpsertPlan(PlateSnapshot? existing, NormalizedDetection det, TimeSource clock);
PlateStats computePlateStats(List<RecognitionEvent> events);
```

All above functions must:
- Avoid hidden state
- Be deterministic relative to input arguments
- Avoid throwing for expected invalid data (return Result/Either or filtered outputs)

---

## 6. Concurrency Model

| Aspect | Policy |
|--------|--------|
| Frame Intake | Serial or bounded queue (size N) to prevent memory bloat |
| Inference | Single active inference at MVP (serialized) |
| Backpressure | Drop (oldest or lowest motionScore) when queue saturated |
| Persistence | Execute on dedicated async executor; short transactions |
| State Emission | Debounced if rapid successive identical updates |
| Cancellation | If new frame arrives while inference busy: store latest frame metadata; do not interrupt ongoing inference (initial) |

Future Option: Introduce inference isolate with message passing (frame descriptor + shared pixel buffer handle).

---

## 7. Sampling Strategies

Strategy options (selectable via config):

| Strategy | Description | Pros | Cons |
|----------|-------------|------|------|
| FixedInterval | Process every N ms | Predictable | Ignores motion variance |
| MotionAdaptive | Skip frames if low motionScore | Saves CPU/Battery | Needs motion estimator |
| ConfidenceAdaptive (future) | Increase interval after high-confidence repetition | Reduces redundancy | Complexity |
| ThermalAware (future) | Expand interval when device hot | Protects device | Requires thermal API |

Baseline formula (MotionAdaptive):
```
if (now - lastProcessedMs < minIntervalMs) skip
if (motionScore < motionThreshold && (now - lastProcessedMs) < maxIdleIntervalMs) skip
process
```

---

## 8. Deduplication Window

Purpose: Prevent multiple near-identical events flooding DB when capturing same plate across successive frames.

Parameters:
- timeWindowMs (default 3000)
- geoDistanceMeters (optional; if GPS stable)
- textMatchStrategy:
  - EXACT (normalized equality)
  - LEVENSHTEIN<=1 (optional for ambiguous single-char)
- minConfidenceDelta (discard if new detection confidence does not exceed previous by threshold)

Algorithm Outline:
1. Filter incoming normalized detections against active window.
2. If identical plate inside window:
   - Update lastSeen & maybe confidence (keep max)
   - Optionally append to ephemeral cluster (not persisted yet)
3. Else treat as new logical recognition.

Window Maintenance:
- Periodically prune entries older than `timeWindowMs`.

---

## 9. Confidence Fusion Heuristics

Base formula (illustrative):
```
fused = raw
fused -= penalty(blurLevel)         // e.g., up to 0.10
fused -= penalty(glareLevel)
fused -= ambiguityPenalty(chars)    // ambiguous char pairs
fused = clamp(fused, 0.0, 1.0)
```

Ambiguity table examples:
- O ↔ 0, B ↔ 8, S ↔ 5, I ↔ 1, G ↔ 6

Heuristic config keys:
- penalty.blur.max
- penalty.glare.max
- penalty.ambiguity.perChar
- min.accepted.confidence (events below are discarded)

---

## 10. Quality Flags (Bitmask)

| Flag | Bit | Meaning | Source |
|------|-----|---------|--------|
| BLUR | 1 << 0 | Motion or focus blur detected | Adapter or preprocessing |
| LOW_LIGHT | 1 << 1 | Underexposed frame | Adapter |
| PARTIAL | 1 << 2 | Bounding box truncated | Adapter geometry |
| GLARE | 1 << 3 | Reflective hotspot | Adapter heuristic |
| AMBIGUOUS | 1 << 4 | Multiple plausible char interpretations | Normalization step |

Quality flags feed into confidence penalties and UI indicators.

---

## 11. Persistence Transaction (Atomic Plan Application)

Plan Steps (imperative shell):
1. Lookup plate by normalized key (cached map + fallback query).
2. Build `UpsertPlan` (pure).
3. BEGIN TRANSACTION.
4. If plan.plate.create: INSERT plate.
5. INSERT recognition event row.
6. If plan.plate.update: UPDATE plate stats fields.
7. COMMIT.
8. Update in-memory cache (plate lastSeen, counts).

On failure:
- ROLLBACK
- Log structured error
- Optionally enqueue retry (bounded attempts) if error is transient (e.g., busy/locked).

---

## 12. Metrics & Instrumentation

| Metric | Type | Description | Target |
|--------|------|-------------|--------|
| frame.intake.fps | gauge | Frames offered per second | Device dependent |
| frame.processed.fps | gauge | Frames entering inference | Adaptive ≤ intake |
| inference.latency.ms.p50/p95/max | histogram | Inference times | p95 < 120ms (MVP) |
| detection.count | counter | Total raw detections | Monitoring volume |
| detection.events.persisted | counter | Recognitions stored (post dedupe) | Volume after filtering |
| dedupe.ratio | gauge | 1 - (persisted / raw detections) | Track effectiveness |
| pipeline.drop.reason.* | counters | Dropped frames reasons | Diagnose sampling |
| db.txn.latency.ms.p95 | histogram | DB transaction times | p95 < 25ms |
| confidence.avg | gauge | Rolling mean fused confidence | Drift detection |
| error.rate | gauge | Failures / operations window | Keep < 5% |

Instrumentation Mode:
- Minimal in production (sampling).
- Full in dev (all logs + debug overlay).

---

## 13. Logging Conventions

Example structured log (JSON conceptual):
```
{
  "ts": 1711111111111,
  "component": "pipeline",
  "event": "recognition_persisted",
  "plate": "ABC123",
  "confidence": 0.87,
  "latency.inference_ms": 42,
  "latency.total_ms": 78,
  "quality_flags": ["BLUR"],
  "model_id": "tflite_v1_fast"
}
```

Event Keys:
- frame_skipped (with reason: INTERVAL, MOTION_LOW, QUEUE_FULL)
- inference_timeout
- inference_error
- dedupe_suppressed
- recognition_persisted
- cache_miss_plate_lookup
- pipeline_degraded (threshold exceeded)
- pipeline_recovered

---

## 14. Failure Modes & Handling

| Failure | Cause | Mitigation | User Impact |
|---------|-------|-----------|-------------|
| Camera stall | Permission revoked, hardware issue | Restart capture attempt, surface banner | Live view stops |
| Inference timeout | Model overload | Skip frame, increment timeout counter | Slight drop in FPS |
| Adapter failure | Model resource corruption | Attempt reload; fallback adapter | Temporary no detections |
| DB lock contention | Long read/other writer | Backoff + retry (small) | Minor latency spike |
| High memory pressure | Large buffers retained | Reduce sampling rate; GC hints | Reduced detection rate |
| Thermal throttling (future) | Device heat | Increase sampling interval | Lower recognition frequency |

Degraded Mode Triggers:
- > X inference timeouts in Y seconds
- P95 inference latency threshold breach
Actions:
- Increase sampling interval
- Reduce optional heuristics (skip charScores)
- Emit pipeline_degraded log

Recovery:
- After stable window (metrics below thresholds) revert configuration.

---

## 15. Configuration (Runtime Tunables)

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| sampling.minIntervalMs | int | 120 | Hard lower bound between processed frames |
| sampling.motionThreshold | double | 0.15 | Motion score below → candidate skip |
| sampling.maxIdleIntervalMs | int | 800 | Force process occasionally to detect static plates |
| inference.timeoutMs | int | 250 | Abandon inference if exceeds |
| inference.queue.max | int | 2 | Max enqueued frames waiting inference |
| detection.minConfidence | double | 0.40 | Discard below fused confidence |
| dedup.timeWindowMs | int | 3000 | Temporal cluster window |
| dedup.geoMeters | double? | null | Geo constraint (if set) |
| dedup.minConfidenceDelta | double | 0.05 | Needed improvement to replace existing event |
| fuse.penalty.blurMax | double | 0.10 | Max blur penalty |
| fuse.penalty.glareMax | double | 0.07 | Max glare penalty |
| fuse.penalty.ambiguityPerChar | double | 0.02 | Ambiguous char penalty |
| cache.plate.maxEntries | int | 5000 | In-memory plate lookup cache size |
| debug.overlay.enabled | bool | false | Dev mode visual overlay |

---

## 16. State Machine (Simplified)

States:
- RUNNING_NORMAL
- RUNNING_DEGRADED
- PAUSED (user action or permissions)
- ERROR (fatal)

Transitions:
- RUNNING_NORMAL → RUNNING_DEGRADED (metrics thresholds breach)
- RUNNING_DEGRADED → RUNNING_NORMAL (recovery criteria)
- Any → PAUSED (camera stop or background)
- Any → ERROR (unrecoverable adapter or DB initialization failure)
- ERROR → RUNNING_NORMAL (manual re-init sequence)

---

## 17. UI Overlay (Dev Mode Aid) – (Future)

Overlay elements:
- Current FPS (intake / processed)
- Inference latency (rolling p50/p95)
- Last detection: plate + confidence
- Pipeline state (NORMAL / DEGRADED)
- Queue depth bar
- Dropped frame reasons counters (rotating)

---

## 18. Example End-to-End Pseudocode

(Conceptual – not final Dart code.)

```
loop on frameStream:
  now = clock()
  if !shouldSampleFrame(state, frame):
     logFrameSkip(frame, reason)
     continue

  enqueue frame (bounded):
     if queueFull -> drop oldest (log reason QUEUE_FULL)

worker inferenceLoop():
  while running:
     frame = dequeue()
     t0 = now()
     result = adapter.detect(frame) with timeout
     tInfer = now() - t0
     if timeout or error:
        recordFailure()
        maybeTriggerDegrade()
        continue

     rawDetections = result
     norm = rawDetections
       .map(r => normalizeAndFuse(r, regionRules, fusionConfig))
       .filter(d => d.fusedConfidence >= config.detection.minConfidence)

     deduped = dedupeDetections(windowBuffer, norm, dedupConfig)
     for each d in deduped:
        existingPlate = plateCache.get(d.plateKey) ?? repo.find(d.plateKey)
        plan = buildUpsertPlan(existingPlate, d, clock)
        txnResult = persistence.apply(plan)
        updateCaches(txnResult)
        emitStateUpdate(d.plateKey)
        logRecognition(d, tInfer)
     pruneWindow(windowBuffer, config.dedup.timeWindowMs)
     updateLatencyStats(tInfer)
     maybeRecover()
```

---

## 19. Testing Strategy (Pipeline Layer)

| Test Type | Focus |
|-----------|-------|
| Unit (pure) | Sampling decisions, dedup logic, fusion penalties |
| Contract | Inference loop with mock adapter providing scripted outputs |
| Load / Soak | 10k synthetic frames, memory growth & latency stability |
| Failure Injection | Force adapter timeouts, DB lock contention |
| Regression Fixtures | Canned raw detection sequences vs expected persisted events |
| Determinism | Same input sequence yields identical persisted state hashes |

Deterministic Mode:
- Fixed clock.
- Mock adapter deterministic mapping frame.id → raw detections.

---

## 20. Performance Targets (Initial)

| Metric | Target |
|--------|--------|
| End-to-end (frame arrival → persisted record) median | < 150 ms |
| Inference P95 mid-tier device | < 120 ms |
| DB transaction P95 | < 25 ms |
| CPU utilization (foreground) | < 40% avg during active scan |
| Memory overhead (adapter + buffers) | < 90 MB total |
| Dropped frames ratio | < 40% (by design sampling) |

---

## 21. Extensibility Points

| Extension | Mechanism |
|-----------|-----------|
| New sampling strategy | Implement strategy interface used by `shouldSampleFrame` |
| Additional heuristics | Add penalty functions composed in fusion step |
| Alternate dedup algorithm | Inject DedupStrategy (time-only, time+geo, fuzzy) |
| Clustering persistence | Introduce cluster builder stage before upsert planning |
| Multi-model voting | Parallel adapters + consensus aggregator (future) |

---

## 22. Security / Privacy Notes

- Pipeline never stores raw frame pixel data beyond immediate inference.
- Sensitive logs (e.g., full plate text) can be masked (config toggle).
- Frame buffers cleared / released promptly after inference.
- No external network calls in MVP pipeline loop.

---

## 23. Observability & Degradation Policy Summary

Degrade when:
- P95 inference latency > threshold for consecutive evaluation windows
- Timeout ratio > configured maximum
- Memory pressure callback (if available) signals high

Actions:
- Increase sampling.minIntervalMs
- Disable optional heuristics (char scores)
- Reduce logging verbosity
- Notify UI (optional indicator)

Recovery:
- Metrics below thresholds for recovery window → restore baseline config.

---

## 24. Open Questions

| ID | Question | Notes |
|----|----------|-------|
| PQ-PIPE-01 | Introduce geohash clustering early? | Might help multi-detection consolidation |
| PQ-PIPE-02 | Use isolates vs single thread for inference? | Benchmark first |
| PQ-PIPE-03 | Persist temporary cluster summary rows? | Useful after large volume scenarios |
| PQ-PIPE-04 | Adaptive minInterval based on confidence trend? | Could reduce redundant highs |
| PQ-PIPE-05 | Add fusion calibration (Platt / isotonic)? | Maybe after dataset collection |
| PQ-PIPE-06 | Real-time watchlist hook placement? | Likely post-dedup pre-persist |

---

## 25. Change Log

| Version | Summary |
|---------|---------|
| 0.1 | Initial recognition pipeline draft |

---

End of document (v0.1)