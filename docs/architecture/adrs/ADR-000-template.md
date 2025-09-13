# ADR-XXX: <Concise Decision Title>

Status: Draft | Proposed | Accepted | Rejected | Superseded by ADR-YYY | Deprecated  
Date: YYYY-MM-DD  
Owner: <engineer/author>  
Reviewers: <list (optional)>  
Version: 1.0  
Backlinks: [[main|Index]] • [[docs/architecture/overview|Architecture]] • [[docs/architecture/pipeline|Pipeline]]

## 1. Context

(Why is this decision needed? What problem / tension / forces exist?  
Keep succinct; link to supporting docs, benchmarks, spikes.)

Examples of contextual elements:
- Problem summary
- Constraints (performance, privacy, offline-first, mobile resource limits)
- Prior related ADRs (list)
- Baseline metrics or pain points
- External references (standards, APIs, model limitations)

## 2. Decision

(One-sentence primary decision first, then elaboration.)
Explicitly state the choice made (technology, pattern, abstraction, policy, contract, etc).

## 3. Options Considered

| Option | Summary | Pros | Cons | Rough Rating* |
|--------|---------|------|------|---------------|
| A | <short> | + ... | - ... | (Low / Med / High) |
| B |  |  |  |  |
| C |  |  |  |  |

(*Rating can be qualitative: alignment, complexity, risk.)

Optional deeper comparison:

### 3.x Option A
Details, rationale, trade-offs.

### 3.x Option B
...

## 4. Decision Drivers (Forces)

| Driver | Importance (H/M/L) | Notes |
|--------|--------------------|-------|
| Performance (latency / memory) |  |  |
| Determinism / Testability |  |  |
| Simplicity / Maintainability |  |  |
| Extensibility / Future Plans |  |  |
| Privacy / Local-only Data |  |  |
| Time-to-Implement |  |  |
| Risk Mitigation |  |  |

Add/remove rows as needed.

## 5. Detailed Rationale

Explain why the chosen option best balances the drivers:
- How it satisfies critical constraints
- Why rejected options fell short
- Any decisive data (benchmarks, complexity deltas)
- Expected lifecycle (is this a stepping stone?)

## 6. Scope & Impact

| Aspect | Impact |
|--------|--------|
| Code Areas | (directories / modules touched) |
| Runtime Behavior | (latency, memory, device usage) |
| Developer Experience | (simpler APIs? new abstractions?) |
| Testing Strategy | (new contract tests? property tests?) |
| Documentation | (which docs updated) |
| Migration | (backfill, data transforms, none) |

## 7. Non-Goals

Clarify expectations and reduce scope creep.  
Example:
- Not deciding packaging / distribution strategy.
- Not locking long-term model format (future ADR).
- Not addressing encryption (future security ADR).

## 8. Risks & Mitigations

| Risk | Type (Perf / Correctness / UX / Security / Ops) | Mitigation / Contingency |
|------|--------------------------------------------------|--------------------------|
|  |  |  |
|  |  |  |

## 9. Dependencies & Prerequisites

List upstream prerequisites (config persistence, adapters, metrics infra).  
Mention if ordering with other ADRs matters.

## 10. Implementation Outline

High-level phased plan (NOT a task dump):
1. Phase 1 – Core scaffolding
2. Phase 2 – Integration / wiring
3. Phase 3 – Hardening / metrics / tests
4. Phase 4 – Cleanup & documentation

## 11. Acceptance Criteria

Bullet list of measurable / verifiable outcomes:
- Feature toggle / config works as described
- Latency regression ≤ X%
- Added tests: (list) with coverage target
- Updated docs: README index + related spec file(s)
- Logs added with structured fields (list if relevant)

## 12. Observability

What metrics/logs confirm success?  
Example:
- New log events: `[PIPELINE] degrade_enter`, `[ADAPTER] swap_success`
- Metrics: latency p95 before/after, memory delta, error rate
- Add to dev overlay? (Yes/No + fields)

## 13. Alternatives Rejected (Optional Deep Dive)

If complexity warranted substantial exploration, capture deeper notes here.

## 14. Open Questions / Follow-Ups

| ID | Question | Resolution Path / Owner | Target ADR? |
|----|----------|-------------------------|-------------|
| OQ-1 |  |  |  |
| OQ-2 |  |  |  |

Close or migrate these when resolved (update Change Log).

## 15. Future Extensions (Roadmap Hooks)

Potential evolutions anchored by this decision:
- Phase 2: GPU delegate evaluation
- Phase 3: Watchlist injection point
- Phase 4: Adaptive calibration pipeline

## 16. Security / Privacy Considerations

State explicitly if:
- No additional data persisted
- Local-only guarantees preserved
- New risk surfaces (e.g., model file integrity)
Provide mitigations or disclaimers.

## 17. Rollback Plan

If results are negative / regressions appear:
1. Toggle off via config flag (if applicable).
2. Revert commits X..Y (list minimal boundary).
3. Purge added data structures (scripts if needed).
4. Post-mortem / follow-up ADR if rollback triggered.

## 18. References

- Related ADRs: ADR-00X, ADR-00Y
- External sources (URLs, papers)
- Benchmark artifacts (path to results)
- Issue / ticket links

## 19. Change Log

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0 | YYYY-MM-DD | <you> | Initial draft |

---

## Template Usage Notes

- Keep ADRs atomic: one major decision per file.
- Use “Superseded by” status rather than deleting outdated ADRs.
- Link ADR from affected docs (Architecture Overview, relevant feature spec).
- Prefer concise core body; push exhaustive benchmarks to separate artifact paths.
- After acceptance: update Status to “Accepted”, add link in README Architecture section.

---

(End of template – copy, replace placeholders, prune unused sections where truly unnecessary.) 
