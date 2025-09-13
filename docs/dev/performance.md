# Performance (Short)

Links: [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]] • [[../data/domain_model|Domain Model]] • [[../data/persistence|Persistence]] • [[../models/model_adapters|Model Adapters]] • [[../ui/features|UI Features]] • [[testing_strategy|Testing]]
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

## Goals
Fast, predictable, low‑overhead recognition: keep median frame→persist latency ≤150 ms (stretch 120), p95 inference ≤120 ms on mid device, memory steady <90 MB added, adaptive sampling protects battery & thermal headroom.

## Core Metrics
| Category | Key Metrics |
|----------|-------------|
| Latency | inference_ms_p50/p95, pipeline_total_ms |
| Throughput | frames_intake_fps, frames_processed_fps |
| Quality | dedupe_ratio, accepted_events / raw_detections |
| Storage | db_txn_ms_p95, db_size_mb |
| Memory | heap_peak_mb, model_resident_mb |
| Stability | timeouts_rate, degrade_mode_transitions |
| Caching | plate_cache_hit_ratio |

## Targets (Initial)
- E2E median ≤150 ms, p95 inference ≤120 ms
- Processed FPS: adaptive 5–10 (sampling governed)
- DB txn p95 ≤25 ms
- Dropped frames (sampling+backpressure) <40%
- Warm model load ≤1 s
- Degrade if p95 inference or timeout ratio exceed thresholds

## Degradation
Trigger: high p95 latency or timeout ratio. Actions: increase sampling interval, disable optional heuristics (e.g. char scores), reduce verbose logs. Recover after stable window below thresholds.

## Flow Levers
1. Adaptive sampling interval
2. Dedup window (time-only ~3s)
3. Buffer reuse (avoid large per-frame allocs)
4. Short WAL transactions
5. Single in‑flight inference (MVP), consider isolates later only if UI jank appears

## Minimal Instrumentation (Prod)
Sampled structured lines:
```
[PIPELINE] e2eMs=132 infMs=87 conf=0.84 plate=ABC123 dedupHit=false
```
Sampling rate adjustable; full metrics only in dev builds / perf harness.

## CI Phases
Fast (PR): unit + contract + micro benchmarks smoke  
Nightly: full benchmark + soak (10k frames) + regression diff  
Block release on: >25% E2E regression, >20% memory delta, major dedupe collapse.

## Benchmark Scenarios
- mock_light (low detection density)
- mock_heavy (every frame detection)
- real_static (stable plate jitter)
- real_mixed
- soak_mock_10k

## Optimization Order
Correctness → Tail latency spikes → Memory growth → Inference mean → DB txn → CPU / battery → Micro tweaks.

## Quick Pseudocode Span Timing
```
t0
 detect()        // inference
 normalize+fuse
 dedupe
 upsert(txn)
 emit
tN
```
Capture each stage; store rolling p50/p95.

## Open Questions
GPU/NNAPI timing? | Introduce geo in dedupe window? | Confidence calibration dataset window? | Early batching gains?

## Summary
Measure first. Keep hot path lean. Adapt under load. Protect determinism for repeatable performance baselines. Defer complexity (multi-thread, GPU) until profiling justifies.

## Change Log
0.2 Short form (Obsidian links, condensed)