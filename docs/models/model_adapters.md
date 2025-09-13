# Model Adapters (Short)

Links: [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]] • [[../data/domain_model|Domain Model]] • [[../data/persistence|Persistence]] • [[../ui/features|UI Features]] • [[../dev/testing_strategy|Testing]] • [[../dev/performance|Performance]]
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

Purpose: Swappable inference layer (TFLite / ONNX / Mock / future Cloud) behind a stable contract.

Core Interface (conceptual):
```dart
abstract class PlateModelAdapter {
  Future<ModelLoadResult> load();
  Future<List<RawPlateDetection>> detect(Frame frame);
  Future<void> dispose();
  ModelMetadata metadata();
}
```

Lifecycle: Uninitialized → Loading → Loaded → (Degraded) → Failed → Disposed.

Key Data:
- RawPlateDetection: rawText, confidenceRaw (0..1), bbox, inferenceTimeMs, qualityFlags
- ModelMetadata: id, version, runtime, inputSpec, supportsBatch
- ModelLoadResult: status, initTimeMs
- ModelHealth (future): state, latencyP95Ms

Performance Targets (see [[../dev/performance|Performance]]):
- p95 inference < ~120ms (mid device)
- Reuse buffers (min allocations)
- Single in-flight detect (MVP)

Error Codes (sample):
MODEL_FILE_MISSING, MODEL_FILE_CORRUPT, INFERENCE_TIMEOUT, PREPROCESS_ERROR, RESOURCE_EXHAUSTED.

Degradation Triggers:
- Latency p95 threshold breach
- Timeout ratio > configured
Actions: raise sampling interval, drop optional heuristics.

Hot Swap (future):
Load new adapter → health check → atomic swap → dispose old.

Testing (see [[../dev/testing_strategy|Testing]]):
- Contract suite (load/detect/dispose)
- Failure injection scenarios
- Deterministic MockAdapter for replay

Security / Privacy:
- No pixel buffer retention after return
- Optional model hash verification (future)

Open Questions:
- Mandatory hash verification?
- Char-level scores default off?
- Batching ROI?
- GPU / NNAPI adoption timing?

Change Log:
0.2 Short form replacement (Obsidian links)

## 1. Purpose

Define a pluggable abstraction for license plate recognition (LPR) models so the application can:
- Swap inference backends (TFLite, ONNX Runtime, native plugin, mock).
- Evolve heuristics independent of UI and persistence.
- Support incremental rollout / fallback logic.
- Enable deterministic test harnesses (mock + replay).

Core principle: The application never depends on a specific ML runtime. Only this contract.

---

## 2. Scope

In-Scope:
- Adapter interface & lifecycle.
- Detection request/response data model.
- Performance & resource management guidelines.
- Error taxonomy.
- Testing strategy (unit+integration).
- Hot swapping semantics.

Out-of-Scope (initial):
- Model training procedures.
- Remote model download/update protocols.
- Federated learning or analytics feedback loops.

---

## 3. High-Level Design

The adapter sits in the Infrastructure layer. A single active adapter instance feeds detections into the recognition pipeline. Multiple adapters may be registered, but only one is “active” at a time (with possible staged warm/standby for fast swap—future).

```
Camera Frames → FrameSampler → Active ModelAdapter → Raw Detections
                                 ↓
                        Normalization / Fusion (Domain)
```

---

## 4. Adapter Interface (Conceptual)

```dart
abstract class PlateModelAdapter {
  /// Load or initialize model resources. Idempotent if already loaded.
  Future<ModelLoadResult> load({ModelLoadMode mode = ModelLoadMode.standard});

  /// Run inference on a frame. May throw ModelInferenceException or return empty list.
  Future<List<RawPlateDetection>> detect(Frame frame, {InferenceOptions? options});

  /// Release native / GPU / memory resources.
  Future<void> dispose();

  /// Metadata describing this adapter + model variant.
  ModelMetadata metadata();

  /// Optional quick health probe (cheap).
  Future<ModelHealth> health();
}
```

---

## 5. Data Structures

### 5.1 `ModelMetadata`
| Field | Type | Notes |
|-------|------|-------|
| `id` | String | Unique stable identifier (e.g. `tflite_v1_fast`) |
| `version` | String | Semantic or hash |
| `runtime` | Enum (`tflite`, `onnx`, `native`, `mock`) | Execution backend |
| `license` | String? | Model usage license snippet/ref |
| `inputSpec` | Shape struct | Width, height, format |
| `supportsBatch` | bool | For potential batching |
| `warmupMsEstimate` | int | Heuristic |

### 5.2 `RawPlateDetection`
| Field | Type | Notes |
|-------|------|-------|
| `rawText` | String | Unnormalized OCR string |
| `confidenceRaw` | double | Raw probability/logit converted to 0..1 |
| `bbox` | Rect | Pixel-space rectangle |
| `charScores` | List<double>? | Optional per-character confidences |
| `inferenceTimeMs` | int | Single pass time |
| `qualityFlags` | int bitmask | BLUR, LOW_LIGHT, PARTIAL, etc. |
| `engineAux` | Map<String, dynamic>? | Adapter-specific metadata (avoid overuse) |

### 5.3 `ModelLoadResult`
| Field | Type | Notes |
|-------|------|-------|
| `status` | Enum: success, partial, failed |
| `warmupRan` | bool | Whether warm inference executed |
| `errors` | List<ModelLoadError> | Non-fatal issues |
| `initTimeMs` | int | Time to load resources |

### 5.4 `ModelHealth`
| Field | Type | Notes |
|-------|------|-------|
| `state` | Enum: healthy, degraded, failed |
| `lastInferenceP95Ms` | int? | Rolling window statistic |
| `memoryFootprintBytes` | int? | Estimate |
| `gcPressureLevel` | Enum: low, medium, high (optional) |

---

## 6. Lifecycle & State Machine

States:
1. `Uninitialized`
2. `Loading`
3. `Loaded`
4. `Degraded` (recoverable anomalies)
5. `Failed`
6. `Disposed`

Transitions:
- Uninitialized → Loading → Loaded
- Loaded → Degraded (on repeated slow inference / soft errors)
- Degraded → Loaded (auto-recovery after window clears)
- Any → Failed (hard error: corrupted model file)
- Loaded/Degraded/Failed → Disposed

Hot Swap Strategy (future incremental):
1. New adapter load in background.
2. Health check new adapter.
3. Atomic pointer swap.
4. Dispose old adapter after draining in-flight tasks.

---

## 7. Loading Modes

| Mode | Behavior |
|------|----------|
| `standard` | Full model + single warm inference |
| `fast` | Minimal load, skip warm; first detect pays penalty |
| `background` | Throttled resource allocation (pre-warm quietly) |
| `diagnostic` | Loads with extra instrumentation / validation passes |

---

## 8. Inference Path (Detailed)

1. Validate frame (dimensions, format).
2. Convert / pre-process (resize, color space, normalization).
3. Run inference (delegate to runtime).
4. Parse raw tensor outputs to candidate strings + metadata.
5. Filter low raw confidence (< adapter min).
6. Construct `RawPlateDetection` objects.
7. Return list (ordering by descending confidence).

Adapter SHOULD:
- Reuse allocated buffers across calls.
- Avoid blocking main (UI) thread.
- Provide per-call timing metrics.

---

## 9. Performance Guidelines

| Topic | Guideline |
|-------|-----------|
| Memory | Keep resident model < ~50–80MB (target), reclaim on dispose |
| Latency | Single-frame inference target < 60ms (mid device) |
| Throughput | Maintain ≥ 10 FPS effective sample capacity (with sampling) |
| Warmup | Warm pass ideally < 500ms |
| Allocation | Zero transient large heap allocations per detect call (use pools) |
| Parallelism | Prefer single-threaded deterministic path first; add isolates only after proof of need |
| Batching | Only when model runtime yields >15% improvement |

Instrumentation (dev mode):
- Inference time histogram (P50, P95).
- Allocation counters (optional).
- Dropped frame reason codes.

---

## 10. Error Taxonomy

| Code | Category | Description | Action |
|------|----------|-------------|--------|
| `MODEL_FILE_MISSING` | Load | Model asset not found | Fail load |
| `MODEL_FILE_CORRUPT` | Load | Hash/signature mismatch | Fail load |
| `RUNTIME_INIT_FAILURE` | Load | TFLite/ONNX context error | Fail load |
| `INFERENCE_TIMEOUT` | Detect | Exceeded configured ms | Mark degraded; escalate |
| `INFERENCE_RUNTIME_ERROR` | Detect | Backend exception | Increment fail counter |
| `PREPROCESS_ERROR` | Detect | Unsupported frame format | Fail detect (skip frame) |
| `RESOURCE_EXHAUSTED` | Detect | OOM-like condition | Attempt recovery once |
| `UNSUPPORTED_OPERATION` | API | Called method not implemented | Developer bug |

All surfaced errors should map to structured logs with adapter id and correlation frame timestamp.

---

## 11. Logging & Observability

Structured fields (example):
```
{
  "component": "model_adapter",
  "adapter_id": "tflite_v1_fast",
  "event": "inference_complete",
  "duration_ms": 42,
  "detections": 2,
  "p95_latency_ms_window": 55
}
```

Degraded state triggers periodic summary logs:
- Rolling failure ratio
- Avg inference latency drift
- Memory footprint anomalies (if measurable)

---

## 12. Configuration Parameters

| Key | Description | Typical Default |
|-----|-------------|-----------------|
| `model.activeId` | Selected adapter id | `tflite_v1_fast` |
| `model.minConfidenceRaw` | Raw detection threshold | 0.30 |
| `model.maxInferenceMs` | Timeout per frame | 250 |
| `model.health.degradeLatencyP95Ms` | P95 latency degrade trigger | 120 |
| `model.health.recoveryWindow` | Window to recover to healthy | 30s |
| `model.enableCharScores` | Request char-level confidences | false (perf trade) |
| `model.preWarm` | Run warm inference at load | true |
| `model.allowConcurrentDetect` | Queue vs reject if busy | false (initial) |

---

## 13. Resource Management

- Use Lazy initialization for large tensor buffers.
- Dispose GPU / NNAPI delegates explicitly.
- Provide `dispose()` idempotency guarantee.
- After dispose: all detect calls must fail fast with defined exception (`AdapterDisposedException`).

---

## 14. Threading & Concurrency

Baseline:
- All adapter operations run on a dedicated isolate OR background executor (platform-specific) to avoid UI jank.
- One detect call at a time unless adapter explicitly supports concurrency.

Concurrency Modes:
| Mode | Description |
|------|-------------|
| `serialized` | Queue; ensures deterministic ordering |
| `parallel-limited` | N concurrent inferences; merge results |
| `speculative` (future) | Cancel slow inference if new higher-priority frame arrives |

Initial Implementation Recommendation: `serialized`.

---

## 15. Security & Integrity Considerations

- Validate model artifact hash (optional enhancement).
- Avoid executing dynamically downloaded native code (until trust scheme defined).
- Zero retention of image data inside adapter after inference returns.
- Strip PII from logs (raw plate text acceptable but optional config to truncate).

---

## 16. Testing Strategy

| Test Type | Focus | Tools |
|-----------|-------|-------|
| Unit | Pre/post-processing, output parsing | Synthetic tensors |
| Contract | `PlateModelAdapter` behavior (load/detect/dispose) | Common harness |
| Performance | Latency & memory | Recorded frames dataset |
| Stability | Long-run (N=10k frames) accumulation | Leak detection counters |
| Error Injection | Simulated corrupt model, timeout | Fault wrappers |
| Mock Adapter | Deterministic sequence | Fixed seeds |

Golden Test Assets:
- Small corpus of frames (blur, low-light, partial occlusion).
- JSON expected detection outputs for mock adapter.

Mock Strategy:
- Deterministic mapping from `frame.id % patterns.length` to canned detection list.

---

## 17. Implementation Variants (Planned)

| Adapter | Runtime | Pros | Cons | Status |
|---------|---------|------|------|--------|
| `TFLiteModelAdapter` | TFLite | Mature, mobile-optimized | Limited dynamic ops | MVP |
| `OnnxRuntimeAdapter` | ONNX Runtime | Wider model ops | Larger binary | Future |
| `MockAdapter` | Pure Dart | Deterministic tests | No real inference | MVP |
| `CloudFallbackAdapter` | HTTP (future) | Heavy compute offload | Latency, privacy | Deferred |

---

## 18. Hot Swap Sequence (Future Outline)

1. User changes model in settings.
2. Controller invokes `load()` on target adapter (inactive).
3. On success → set as pending active.
4. Drain current inference queue.
5. Atomic swap reference.
6. Dispose old adapter after grace period.
7. Emit `ModelSwapped` event to observers.

Failure (new adapter load failed):
- Keep existing adapter active.
- Surface UI error + revert selection.

---

## 19. Integration Points

| Component | Interaction |
|-----------|------------|
| FrameSampler | Supplies selected frames |
| Recognition Orchestrator | Calls `detect()` & merges results |
| Settings / Config Store | Provides active adapter id |
| Logging Subsystem | Receives structured events |
| Persistence (optional) | Stores aggregated metrics (future) |

---

## 20. Metrics (Dev Mode)

| Metric | Definition |
|--------|------------|
| `inference.count` | Total detect invocations |
| `inference.detections.sum` | Count of raw detections returned |
| `inference.latency.ms.p50/p95/max` | Rolling latency stats |
| `inference.fail.ratio` | Failures / total |
| `adapter.memory.bytes` | Best-effort snapshot |
| `adapter.degraded.seconds` | Time spent in degraded state |

Collection Recommendation:
- Ring buffer or streaming aggregator (avoid heavy libs).
- Snapshot flush every N seconds or on state change.

---

## 21. Degradation Policy (Heuristic)

Trigger degrade if:
- P95 latency > `degradeLatencyP95Ms` for Y consecutive windows
OR
- Failure ratio > 0.15 over last 50 calls
OR
- 3 consecutive timeouts

Recovery if:
- P95 latency < threshold for Z consecutive windows AND
- Failure ratio < 0.05

Escalate to failed if:
- > K consecutive load failures OR
- Resource exhaustion repeats after immediate recovery attempt.

---

## 22. Adapter Selection Algorithm (Initial)

```
function selectAdapter(desiredId, registry):
    if desiredId in registry:
        return registry[desiredId]
    fallbackOrder = [tflite_any, mock]
    for candidate in fallbackOrder:
        if candidate in registry:
            return registry[candidate]
    throw NoAdapterAvailable
```

Future: add capability scoring (e.g., region coverage, latency rating).

---

## 23. Open Questions

| ID | Topic | Question |
|----|-------|----------|
| MQ-01 | Hash Verification | Do we mandate model hash validation MVP? |
| MQ-02 | Multi-plate per frame | Need NMS (non-max suppression) tuning doc? |
| MQ-03 | Char-level features | Useful for advanced heuristics or premature? |
| MQ-04 | Dynamic quantization | Should runtime choose int8 vs float automatically? |
| MQ-05 | Batch vs single | Empirical threshold for batching effectiveness? |

---

## 24. Future Enhancements

| Feature | Rationale |
|---------|-----------|
| Adaptive Model Switch | Choose model based on thermal / battery constraints |
| Confidence Calibration | Platt scaling or isotonic post-training |
| Per-Region Submodels | Optimize accuracy by locale |
| On-Device A/B Testing | Compare two adapters invisibly |
| Incremental Model Updates | Download delta patches |
| GPU / NNAPI Delegation | Lower latency / power usage |
| Edge Cloud Hybrid | Offload on poor local perf conditions |

---

## 25. Glossary

| Term | Definition |
|------|------------|
| Adapter | Component implementing inference contract |
| Warmup | First inference to initialize kernels / JIT |
| Degraded | Performance below acceptable thresholds but still functional |
| NMS | Non-Maximum Suppression (duplicate candidate pruning) |
| Fusion (outside adapter) | Post-processing combining raw scores + heuristics |
| Hot Swap | Live replacement of active inference adapter |

---

## 26. Change Log

| Version | Date | Summary |
|---------|------|---------|
| 0.1 | (bootstrap) | Initial adapter spec draft |

---

End of document (v0.1)