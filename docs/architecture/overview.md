# Architecture Overview (Short)

High-level map of PlateRunner architecture.
Links: [[pipeline|Pipeline]] • [[../data/domain_model|Domain Model]] • [[../data/persistence|Persistence]] • [[../models/model_adapters|Model Adapters]] • [[../ui/features|UI Features]] • [[../dev/testing_strategy|Testing]] • [[../dev/performance|Performance]] • [[../features/todo/README|Feature TODOs]]
Backlinks: [[main|Index]] • [[pipeline|Pipeline]] • [[../dev/performance|Performance]]

---

## 1. Goals
Offline-first, sub‑second feedback path, deterministic core, swappable ML models, low battery overhead, privacy (local only), clear extension seams.

Non-goals (MVP): cloud sync, model training pipeline, auth, evidence-grade forensics.

---

## 2. Layers
```
UI → Use Cases → Domain (pure) → Infrastructure (DB / Camera / Models) → Platform
```
Rule: Domain never imports UI/Infra; dependencies flow downward via interfaces.

---

## 3. Core Concepts
Plate, RecognitionEvent, PlateRecord, ModelAdapter, Dedup Window, Fused Confidence, Upsert Plan (see [[../data/domain_model|Domain Model]]).

---

## 4. Functional Core vs Shell
Pure: normalization, confidence fusion, dedup, upsert planning.  
Shell: frame capture, model invocation, persistence, logging, GPS.

Benefits: high test coverage, predictable refactors, easy adapter swaps.

---

## 5. Module Sketch
`features/*` (screens), `domain/*` (pure logic), `app/usecases` (orchestration), `infrastructure/*` (db, camera, adapters), `shared/*` (utils/config), `ui/` (theme/widgets).

---

## 6. Recognition Flow (Condensed)
Camera → Sample → Adapter.detect → Normalize + Fuse → Dedup → Upsert (SQLite) → Emit state → UI update.

Details: [[pipeline|Pipeline]].

---

## 7. Persistence Snapshot
Tables: `plates`, `recognitions`. Indexed on normalized plate + (plate_id, ts). Migration versioning; all local. More in [[../data/persistence|Persistence]].

---

## 8. Extensibility Points
- ModelAdapter implementations
- Sampling strategies
- Region normalization rules
- Confidence penalties
- Dedup strategy params

---

## 9. Performance Levers
Adaptive sampling, frame dedup window, buffer reuse, lightweight DTO mapping, short DB transactions. Targets & budgets: [[../dev/performance|Performance]].

---

## 10. Observability
Structured logs: `[PIPELINE]`, `[MODEL]`, `[DB]`. Dev overlay (FPS, latency, dedup ratio). Planned metrics: inference p95, txn p95, cache hit rate.

---

## 11. Security & Privacy
No raw frame storage; purge support; optional future encryption. No network in MVP.

---

## 12. Config (Runtime)
Active model id, min confidence, dedup window ms, sampling interval/strategy, GPS optional flag. Centralize in config service.

---

## 13. Implementation Order (MVP)
1. Domain primitives + normalization/dedupe
2. SQLite schema + repo interfaces
3. Mock adapter + scan loop
4. Real adapter + performance metrics
5. History + plate detail
6. Settings + config persistence
7. Testing matrix & dev overlay
8. Optimization & polish

---

## 14. Open Questions (Top)
- Region format modularization timing
- Time vs time+geo dedup default
- State management (Riverpod?)
- Confidence calibration need post data collection
- GPU/NNAPI delegate adoption timing

---

## 15. Mini Diagram
```
[UI] → [UseCases] → [Domain] → [Infra(DB/Model/Camera)] → SQLite
                 ↑        |
           (events/state) |
```

---

## 16. Related Docs
Links: [[pipeline|Pipeline]] • [[../data/domain_model|Domain Model]] • [[../data/persistence|Persistence]] • [[../models/model_adapters|Model Adapters]] • [[../ui/features|UI Features]] • [[../dev/testing_strategy|Testing]] • [[../dev/performance|Performance]]

---

Revision: v0.2 (short form / Obsidian links)
