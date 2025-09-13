# Feature TODO Index
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

Central index of active and planned feature specifications / TODO documents for PlateRunner.  
These documents capture goals, scope, requirements, architecture touch points, phased implementation, open questions, risks, and definition-of-done checklists.  
They are intentionally lightweight living specs—update them as decisions are made or scope evolves.

---

## Current TODO Specs

| Feature | File | Status | Primary Themes | Depends On |
|---------|------|--------|----------------|------------|
| Runtime Config Persistence | `runtime_config_persistence.md` | Draft v0.1 | Config durability, bootstrap sequence, debounced writes | `lib/shared/config/runtime_config.dart` |
| Recognition Pipeline (Core) | `recognition_pipeline.md` | Draft v0.1 | Frame → Detect → Normalize/Fuse → Dedup → Persist → Emit | Architecture pipeline docs |
| Developer Overlay UI | `dev_overlay_ui.md` | Draft v0.1 | Live metrics, diagnostics, throttled updates, minimal overhead | Pipeline metrics collector |
| Plate History & Detail | `plate_history_feature.md` | Draft v0.1 | Browsing past recognitions, stats aggregation, pagination | Pipeline persistence & deltas |

---

## Cross-Cutting Themes

| Theme | Touch Points |
|-------|--------------|
| Performance Budgets | Recognition pipeline, config persistence debounce, overlay throttling |
| Determinism & Testability | Pure domain functions (fusion, dedup, plan build) |
| Observability | Structured logging, metrics snapshots, dev overlay consumption |
| Privacy & Data Retention | No raw frames; configurable purge paths; history feature purge/delete |
| Runtime Configuration | Single source of truth (`RuntimeConfigService`) powering multiple features |

---

## Implementation Order (Suggested)

1. Recognition Pipeline primitives & orchestrator (unblocks metrics + history deltas)
2. Runtime Config Persistence (enables stable tuning across restarts)
3. Plate History repositories & controllers (consumes pipeline outputs)
4. Dev Overlay UI (visualizes metrics/state; aids performance tuning)
5. Hardening passes (degradation heuristics, robust logging, tests)
6. Optional polish & future enhancements (charts, watchlist hooks, export)

---

## Conventions for New TODO Specs

When adding a new feature TODO file under this directory:

1. File name: `snake_case_feature_name.md`
2. Begin with header:
   ```
   # Feature TODO: Descriptive Name
   Status: Draft (v0.1)
   Owner: (assign)
   Related Docs: (list)
   ```
3. Recommended Sections (trim if N/A):
   - Goal
   - Scope (In / Out)
   - Non-Goals
   - User Stories / Functional Requirements
   - Data / Domain Model
   - Architecture / Interfaces
   - Performance / Constraints
   - Logging / Observability
   - Error Handling
   - Privacy / Security
   - Testing Strategy
   - Risks & Mitigations
   - Implementation Phases
   - Open Questions
   - Definition of Done
   - Task Checklist
   - Change Log

4. Keep actionable checklist near bottom for quick scanning.
5. Update this README table with the new feature entry.

---

## Status Legend

| Status | Meaning |
|--------|---------|
| Draft | Initial outline; details may change |
| In Progress | Actively being implemented |
| Review | Awaiting validation / PR review |
| Complete | Implemented + tests + docs updated |
| Deferred | Intentionally postponed |

---

## Linking & Traceability

- Architecture references should prefer relative links (e.g., `../architecture/pipeline.md`).
- Cross-feature dependencies: ensure each spec lists upstream (inputs) and downstream (consumers).
- When a major decision is made (e.g., strategy selection), update the spec and increment version in its Change Log.

---

## Maintenance Guidelines

- Keep specs concise; if a section becomes outdated or irrelevant, prune it.
- Prefer additive versioned changes over large rewrites—retain rationale in Change Log.
- Sync Definition of Done items with real implementation checkpoints (tests, logging, metrics).
- Close Open Questions explicitly (mark with resolution or removal).

---

## Quick Links

- Pipeline Architecture: `../architecture/pipeline.md`
- Architecture Overview: `../architecture/overview.md`
- (Future) Domain Model: `../data/domain_model.md` (create once ready)
- Performance Targets: `../dev/performance.md`

---

Revision: v0.1 (initial index)
