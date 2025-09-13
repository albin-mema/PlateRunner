# PlateRunner Index

Offline-first mobile LPR (license plate recognition) in Flutter. This index uses Obsidian-style wiki links for fast graph navigation.

## Core Flow
Camera → sample → model → normalize → fuse confidence → dedupe → persist → emit → UI

### Immediate Implementation Focus (Sprint)
1. Camera preview & permission flow (rear camera).
2. Frame sampling throttle (config-driven).
3. Model load (TFLite or mock) + inference loop (single in-flight).
4. Domain normalize + confidence fuse + time-window dedupe (in-memory).
5. Minimal overlay (boxes + plate + confidence).
6. File/image import: run single inference for static test images.
7. Structured dev logs `[PIPELINE]` with latency + counts.
8. (Next) Lightweight persistence & history after loop is stable.


## Key Docs
(Condensed quick links kept for convenience; see full Documentation Index below.)
- [[docs/architecture/overview|Architecture]]
- [[docs/architecture/pipeline|Pipeline]]
- [[docs/data/domain_model|Domain Model]]
- [[docs/data/persistence|Persistence]]
- [[docs/models/model_adapters|Model Adapters]]
- [[docs/ui/features|UI Features]]
- [[docs/dev/testing_strategy|Testing]]
- [[docs/dev/performance|Performance]]
- [[codestyle|Code Style]]

## Documentation Index

### Architecture
- [[docs/architecture/overview|Architecture Overview]]
- [[docs/architecture/pipeline|Recognition Pipeline]]
- [[docs/architecture/adrs/ADR-000-template|ADR Template]]

### Domain & Data
- [[docs/data/domain_model|Domain Model]]
- [[docs/data/persistence|Persistence]]

### Models
- [[docs/models/model_adapters|Model Adapters]]

### Feature / Pipeline Specs (TODOs)
- [[docs/features/todo/recognition_pipeline|Recognition Pipeline Impl Spec]]
- [[docs/features/todo/runtime_config_persistence|Runtime Config Persistence]]
- [[docs/features/todo/dev_overlay_ui|Dev Overlay UI]]
- [[docs/features/todo/plate_history_feature|Plate History Feature]]
- [[docs/features/todo/README|Feature TODO Index]]

### UI / UX
- [[docs/ui/features|UI Features]]

### Engineering Practices
- [[docs/dev/testing_strategy|Testing Strategy]]
- [[docs/dev/performance|Performance Targets]]
- [[codestyle|Code Style]]

### Governance & AI
- [[agents|AI Agents Guide]]

### How to Extend Docs
1. Create a concise “short” doc; deep rationale goes to an ADR or feature spec.
2. Add a bullet under the correct category above.
3. Add contextual cross‑links (relative paths) to related docs.
4. Include a backlink to this index (see Backlinks section).

## Backlinks
All substantive docs should include a quick backlink so navigation graphs remain connected:

Recommended snippet to place near top or bottom:
```
Links: [[main|Index]] • [[docs/architecture/overview|Architecture]] • [[docs/architecture/pipeline|Pipeline]]
```
(Use only the most relevant links for brevity.)

## Pillars
Offline | Modular ML | Functional Core | Adaptive Performance | Privacy | Extensible

## Repo Layout
```
lib/
  main.dart
  domain/  app/  features/  infrastructure/  shared/  ui/
test/
  domain/  app/  infrastructure/  pipeline/  ui/  fixtures/  utils/
```

## Quick Contribution
1. Implement/iterate camera → adapter → overlay loop first (no premature features).
2. Keep logic pure inside `domain/` (no platform, no logging).
3. After loop works, add persistence + history UI stubs.
4. Add/expand tests (see [[docs/dev/testing_strategy|Testing]]) once behavior stabilizes.
5. Profile & tune only after baseline metrics captured (see [[docs/dev/performance|Performance]]).

## Cross-Cutting Concepts
PlateRecord | RecognitionEvent | Dedup Window | Fused Confidence | Upsert Plan | Adapter Lifecycle

## Fast Links
[[docs/architecture/pipeline|Pipeline Stages]] • [[docs/ui/features|UI Screens]] • [[docs/data/domain_model|Entities]] • [[docs/dev/testing_strategy|Test Strategy]] • [[docs/dev/performance|Perf Budgets]]

## Open Questions (Sample)
State mgmt (Riverpod?) | Region formats modularization | Time+geo dedupe baseline | Confidence calibration timing

## Glossary (Mini)
LPR, Functional Core, Imperative Shell, Dedup Window, Fused Confidence, Upsert Plan

## Change Log
1.4 Added comprehensive Documentation Index + Backlinks guidance  
1.3 Refocus: implementation priorities (camera/model/import) + updated contribution steps  
1.2 Repo layout realized (created directories & initial domain scaffolds)  
1.1 Shortened + Obsidian links + Code Style link
