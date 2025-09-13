# Testing Strategy (Short)

Links: [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]] • [[../data/domain_model|Domain Model]] • [[../data/persistence|Persistence]] • [[../models/model_adapters|Model Adapters]] • [[../ui/features|UI Features]] • [[performance|Performance]]
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

Goal: Fast feedback & high determinism: pure domain unit + property tests (majority), contract tests for adapters/repos, pipeline replay scenarios (hash comparison), focused integration tests, minimal but meaningful widget/golden tests, nightly performance & soak runs.

---

Define a pragmatic, risk‑focused, automation‑heavy testing approach that:
- Preserves correctness of pure domain logic (Functional Core).
- Rapidly detects regressions in the recognition pipeline.
- Supports safe refactors & extensibility (model adapters, sampling strategies).
- Minimizes flakiness & maintenance overhead on mobile platforms.
- Enables confident iterative delivery (short feedback cycles).

---

## 2. Scope

In-Scope:
- All Dart / Flutter code (domain, use cases, infra, UI).
- SQLite schema migrations.
- Model adapter contracts (through mocks & harnesses).
- Performance & resource sanity (latency, memory signals).
- Deterministic pipeline replay tests.

Out-of-Scope (Initial):
- End-to-end real camera hardware tests on device farms (may add smoke later).
- Cloud sync scenarios (not in MVP).
- Full security penetration testing (future specialized effort).

---

## 3. Test Taxonomy Overview

Layered around the architecture:

| Layer | Primary Test Types | Goal |
|-------|--------------------|------|
| Domain (pure) | Unit, Property-based | Mathematical certainty & invariants |
| Application Use Cases | Contract, Integration (with fakes) | Orchestration correctness |
| Infrastructure (DB, Adapters) | Integration, Migration, Contract | Boundary reliability |
| Pipeline | Scenario Replay, Determinism, Load | Correct staged transformations |
| UI | Widget, Golden, Interaction | Stable rendering + flows |
| Cross-Cutting | Performance, Soak, Mutation (future) | Non-functional assurances |
| Tooling / Config | Smoke | Guardrail on dev ergonomics |

---

## 4. Architectural Alignment

Functional Core = heavy unit & property tests (fast, isolated).  
Imperative Shell = thin integration & contract tests validating side-effects and wiring.  
Goal: >80% of total test volume in pure domain / deterministic categories.

---

## 5. Test Pyramid (Target Shape)

- Base: Pure Domain Unit + Property (~50–55%)
- Mid: Use Case + Infra Integration (~25–30%)
- Upper: UI Widget + Golden (~10–15%)
- Thin Cap: Scenario / Performance / Soak / Mutation (<5%)

Avoid inverted pyramid (too many brittle UI tests).

---

## 6. Test Types (Detailed)

### 6.1 Domain Unit Tests
- Functions: `normalizePlate`, `fuseConfidence`, `dedupeEvents`, `buildUpsertOps`.
- Assert invariants, edge cases, error codes.
- Zero mocks—only value objects and test data builders.

### 6.2 Property-Based Tests
Targets:
- Normalization idempotence (normalize(normalize(x)) == normalize(x)).
- Deduplication window monotonicity (adding an event outside window increases size).
- Confidence clamp (∀ inputs -> result ∈ [0,1]).
Framework: Introduce lightweight property runner (custom or existing Dart lib).

### 6.3 Use Case / Application Tests
- Example use cases: “Ingest frame → recognition persisted”, “Update plate metadata”.
- Use fakes for DB & model adapter (in-memory implementation).
- Validate external effect ordering.

### 6.4 Infrastructure Integration Tests
- SQLite migrations (bootstrap from baseline version → latest).
- Foreign key enforcement, index usage (EXPLAIN sanity for critical queries).
- ModelAdapter mock: simulate load / detect / failure paths.

### 6.5 Pipeline Scenario Replay
- Recorded synthetic frame sequence → expected persisted recognition set / ordering.
- Deterministic clocks & adapter outputs.
- Hash persisted result to detect regression (`snapshot.json` or computed digest).

### 6.6 UI Widget Tests
- Isolated: `RecentPlatesStrip`, `ConfidenceChip`.
- Interaction: tap plate in live overlay → navigates to detail.
- Use fake providers / Riverpod overrides (if Riverpod selected).

### 6.7 Golden Tests
- Plate detail header (with notes, no notes, flags).
- Settings panel states (model loading, error).
- Dark vs light theme snapshots.

### 6.8 Performance Tests (Micro + Pipeline)
Metrics:
- Inference loop (mock adapter) sustained frames processed per second.
- DB transaction latency P95 for N recognitions (e.g., 1k batch).
Trigger: Run in CI nightly / on demand (not every PR).

### 6.9 Soak / Stability Tests
- Long-running pipeline simulation (e.g., 10k synthetic frames).
- Assert no memory leak indicators, bound queue length never exceeds limit.

### 6.10 Migration Tests
- Down-level DB fixture → apply new migrations → validate schema & surviving data.
- Tamper mismatch (e.g., missing index) → ensure migration repairs or fails clearly.

### 6.11 Contract Tests
- Adapter Contract: shared test suite applied to each adapter implementation (mock + future TFLite).
- Repository Contract: common CRUD, predicate, pagination semantics.

### 6.12 Fuzz / Robustness (Selective)
- Plate input fuzzing (random alphanumeric, punctuation) → expect either normalized or structured error.
- Confidence fusion boundary floats (NaN, ±∞) → coerced or rejected gracefully.

### 6.13 Mutation Testing (Future)
- Apply mutation tool to domain layer to identify weak assertions.
- Run periodically (manual gating) rather than every PR (costly).

### 6.14 Security / Privacy Spot Checks (Future)
- Ensure plate purge removes recognition events.
- No residual frames retained in memory caches after disposal (approximation via indirect assertions).

---

## 7. Determinism Strategies

| Aspect | Approach |
|--------|----------|
| Time | Inject `TimeSource` / provide fixed epoch in tests |
| UUIDs | Use seeded fake ID provider for stable outputs |
| Random Heuristics | Avoid RNG; if required, inject deterministic PRNG |
| Concurrency | Force single-thread / serialized execution path in tests |
| Floating Math | Round or assert within epsilon |

---

## 8. Test Data Management

Patterns:
- Builders (fluent) for `RecognitionEvent`, `Plate`, `RawPlateDetection`.
- Inline small fixtures; large sequences stored as JSON under `test/fixtures/`.
- Snapshot outputs (hash or JSON) versioned & reviewed—never auto-overwritten.
- For golden images: store minimal diff-friendly PNGs (compress carefully).

Naming Convention:
`plate_builder.dart`, `detection_fixtures.dart`, `scenario_live_loop_test.dart`.

---

## 9. Directory Structure (Proposed)

```
test/
  domain/
    normalization/
    confidence/
    dedup/
  app/
    usecases/
  infrastructure/
    db/
    adapters/
    migrations/
  pipeline/
    scenarios/
    performance/
  ui/
    widgets/
    golden/
  fixtures/
    sequences/
    migrations/
  utils/
    builders/
    fakes/
```

---

## 10. Fakes / Mocks / Stubs Guidance

| Type | Use Case | Rules |
|------|----------|-------|
| Fake | In-memory repository / adapter | Preferred for integration |
| Stub | Return canned detection list | Only when behavior trivial |
| Mock (spy) | Verify side-effect call order | Minimize usage; domain tests avoid |
| Dummy | Placeholder object unused | Rare (avoid noise) |

Prohibition: Avoid deep mock chains; rewrite test to assert observable state instead.

---

## 11. Assertion Style

- Favor exact structural equality (deep compare) for domain outputs.
- Use helper matchers: `expectPlateStats(stats, total: 3, firstSeen: t0, lastSeen: t2)`.
- Confidence numeric: assert within epsilon (e.g., ±0.0001).
- For ordering: assert explicit sequence lists (not just length).

---

## 12. Coverage Targets (Guidelines, not rigid)

| Layer | Target % | Rationale |
|-------|----------|-----------|
| Domain (pure) | 95%+ | High ROI, deterministic |
| Use Cases | 85% | Orchestration |
| Infrastructure DB | 70–80% | Focus critical paths & migrations |
| Pipeline Core (logic) | 85% | Frame/detection transformation |
| UI Widgets | 60–70% | Avoid brittle over-testing |
| Overall | 80% | Balanced maintainability |

Quality > chasing %; exclude generated code & trivial DTOs.

---

## 13. CI Pipeline (Proposed Stages)

1. Lint / Static Analysis (`dart analyze`)
2. Fast Unit (domain + pure) tests
3. Core Integration (DB + pipeline scenarios)
4. Widget & Golden tests (headless)
5. Coverage report generation (fail if below floor)
6. (Nightly) Performance & Soak suite
7. (Optional) Mutation test (manual trigger)
8. Artifact publish: coverage badge, performance trend JSON

Fail-Fast Policy: Stop pipeline on first failing stage (except nightly extras).

---

## 14. Flakiness Mitigation

| Risk | Strategy |
|------|----------|
| Async timing | Use deterministic clocks / pump with explicit durations |
| Animation frames | Disable or set reduced motion flag in widget tests |
| DB concurrency | Single-writer usage; wrap each test in fresh in-memory DB |
| Golden drift | Pin fonts & theme tokens; review diff threshold = zero |
| Random seeds | Fixed seeds, log seeds in failure output |

Quarantine Label: Tag flaky test -> tracked issue -> must be resolved before release branch cut.

---

## 15. Performance Benchmarking (Lightweight)

Scope:
- Mock adapter inference loop (N frames).
- DB batch insert (1k recognitions).
- Dedup throughput under synthetic burst (e.g., same plate rapid sequence).

Metrics captured to JSON (commit id, timestamp, metrics). Trend file stored in repository or external artifact storage.

Threshold Alerts (soft):
- Inference loop median latency regression > +20% vs 7-day moving average.
- DB txn P95 > 2x baseline.

---

## 16. Tooling & Utilities

| Need | Utility |
|------|--------|
| Time control | `TestTimeSource` |
| ID generation | `DeterministicIdGenerator(seed)` |
| Frame factory | `TestFrameFactory.sequence(count, motionPattern)` |
| Adapter fake | `ScriptedAdapter(scriptFrames → detections[])` |
| DB harness | `InMemoryDbHarness.applyMigrations()` |
| Snapshot | `SnapshotHasher.fromEvents(list)` (algorithm: stable JSON → SHA256) |

---

## 17. Migration Testing Strategy

For each new migration version:
1. Start from base schema (v0).
2. Apply sequential migrations to target.
3. Assert new tables/indices exist.
4. Insert legacy-shaped data pre-migration where needed.
5. Validate upgraded data shape & constraints.
6. Run integrity check query.

Store down-level `fixtures/migrations/vX_base.db` (if size modest).  
Alternative: Programmatically create vX schema for reproducibility.

---

## 18. Regression Snapshot Strategy

Critical scenario (e.g., multi-frame dedup) produces:
- Final persisted rows (ordered by ts)
- Derived stats object
Serialized → canonical JSON (sorted keys) → hashed.  
Commit expected hash; test re-computes & compares.  
If change intentional, update fixture + add CHANGELOG note.

---

## 19. Risk-Based Prioritization (Initial High-Risk Areas)

| Area | Risk | Mitigation |
|------|------|------------|
| Dedup logic | Silent data inflation or loss | Extensive boundary tests + property tests |
| Normalization | Mis-keyed plates | Multi-locale pattern tests |
| Persistence | Migration corruption | Versioned migration suite |
| Adapter integration | Runtime crashes | Contract + failure injection tests |
| Performance sampling | Overload / battery drain | Load & throughput tests in CI |
| Purge operation | Privacy violation if incomplete | Purge + post-assert row counts zero |

---

## 20. Test Naming Conventions

Pattern: `<Subject>_<Condition>_<Expectation>()`

Examples:
- `NormalizePlate_mixedCaseAndSpaces_returnsCanonicalUpper()`
- `DedupeEvents_samePlateWithinWindow_collapsesToSingle()`
- `IngestUseCase_newPlate_persistsPlateAndEvent()`

---

## 21. Coding Conventions in Tests

| Rule | Reason |
|------|--------|
| One logical assertion group per test | Clarity (allow multiple expects within group) |
| Avoid logic in test bodies | Reduce cognitive load |
| Extract repeated arrange steps into helpers | DRY without obscuring intent |
| Keep test files < 400 lines | Navigability |
| Prefer explicit test data over random unless property test | Debug reproducibility |

---

## 22. Failure Diagnostics

On failure:
- Dump minimal contextual diff (e.g., expected vs actual normalized strings).
- Provide reproduction hint (seed / scenario name).
- For pipeline scenario failing hash: output delta summary (counts: added, removed, modified).

---

## 23. Code Review Checklist (Tests)

- Does the test assert behavior, not implementation detail?
- Are edge cases covered (null/empty, boundary thresholds)?
- Any overuse of mocks that could be replaced with fakes?
- Are time / randomness sources injected?
- Is fixture size minimal & readable?

---

## 24. Continuous Improvement Metrics

Track (quarterly):
- Test execution time (median & P95).
- Flake rate (% reruns).
- Coverage trends per layer.
- Mutation score (when adopted).
- Defect escape rate (bugs found post-merge).
Goal: Use metrics to prune low-value or flaky tests.

---

## 25. Open Questions

| ID | Question | Notes |
|----|----------|-------|
| TQ-01 | Adopt Riverpod test harness now or later? | Depends on state mgmt ADR |
| TQ-02 | Introduce mutation testing early? | Possibly after stable baseline |
| TQ-03 | Run UI golden tests on all PRs? | Might gate only changed UI directories |
| TQ-04 | Add device farm smoke tests? | Post-MVP for real camera feed |
| TQ-05 | Formal property-based library selection? | Evaluate available Dart libs |
| TQ-06 | Snapshot serialization format (JSON vs binary)? | JSON (human diffable) |
| TQ-07 | Integrate static contract check (e.g., code gen)? | Future exploration |

---

## 26. Future Enhancements

| Idea | Benefit |
|------|---------|
| Differential Performance Baseline | Early detection of throughput regressions |
| Visual Pipeline Timeline Tool | Debug multi-stage latency spikes |
| Synthetic Data Generator CLI | Automated scenario expansion |
| Inference Trace Export | Offline analysis of adapter performance |
| Partial Mutation Testing (Critical Functions Only) | Boost confidence in heuristics |
| Coverage Heatmap Visualization | Identify untested branches quickly |

---

## 27. Change Log

| Version | Summary |
|---------|---------|
| 0.1 | Initial comprehensive testing strategy scaffold |

---

End of document (v0.1)