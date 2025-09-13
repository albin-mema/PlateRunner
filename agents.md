# AI Agents Context Reduction Guide (PlateRunner)

Purpose:
Provide a minimal, practical checklist for making this repository *agent‑friendly* by:
1. Reducing token/context size.
2. Increasing navigability (dense, reliable links).
3. Encouraging small, composable code & doc units.

No process governance, no speculative roles—just concrete tactics.

---

## 1. Core Principles

| Principle | Action |
|----------|--------|
| Small Surfaces | Split >400 line files (code or docs). |
| Link Everything | Every substantive doc + feature spec has backlinks + forward links. |
| Stable Anchors | Use consistent headings (no churn) so anchors stay valid. |
| Co-locate Context | Keep rationale near code entrypoints via short top comments + link outward. |
| Minimize Boilerplate | Remove dead code & stale commented blocks quickly (noise costs tokens). |
| Deterministic Names | Prefer explicit filenames over generic helpers to ease targeted retrieval. |

---

## 2. Required Sections in New Docs

At top of each new doc (copy & adapt):

```
Links: [[main|Index]] • [[docs/architecture/overview|Architecture]] • (add 2–3 most related)
Backlinks: [[main|Index]]
```

Keep links ≤ ~6 to avoid clutter. Prefer breadth over duplication.

---

## 3. README / Index Hygiene

When adding:
- New feature spec → update:
  - README Reference & Documentation Index
  - main.md Documentation Index
- New ADR → add under Architecture + link from impacted spec(s).
- Remove deprecated docs → replace with stub pointing to successor for 1–2 releases.

---

## 4. File Size Targets

| Type | Preferred Max | Hard Split Trigger |
|------|---------------|--------------------|
| Dart pure logic | 250 lines | 350 lines |
| Feature controller | 300 lines | 400 lines |
| Widget file | 250 lines | 350 lines |
| Spec / doc (short form) | 250 lines | 320 lines |
| ADR (active) | 300 lines | 400 lines |

Rationale: Keeps single-file ingestion cheap for agent prompts.

---

## 5. Linking Patterns

| Need | Pattern |
|------|--------|
| Feature spec ↔ pipeline | In spec: link pipeline stage; in pipeline doc: link spec section. |
| Domain model ↔ persistence | Each entity definition links to storage schema area. |
| Testing strategy ↔ code | Add one-line link in test folder README to relevant specs. |
| ADR adoption | At decision point in code comment: `// ADR-012: reason (link)` |

Example in code:
```dart
// Confidence fusion adjustments (ADR-007):
// Rationale & thresholds: docs/architecture/adrs/ADR-007-confidence-fusion.md
```

---

## 6. Suggested Directory Micro-Index Files

Add (tiny) `_index.md` (or README.md) where folders grow:
- `lib/domain/` → brief map + links to core value objects
- `lib/features/recognition/` → controllers & widgets list
- `test/` subfolders → what each covers + spec references

Goal: Agents read one micro-index to decide which concrete files to open.

---

## 7. Code Comment Strategy (Context Hooks)

At top of non-trivial files (≤5 lines):
```
/// Purpose: (what it does in one line)
/// Links: (1–2 doc anchors)
/// Notes: (performance or architectural constraint)
```
Avoid repeating detailed rationale (lives in spec/ADR).

---

## 8. Prompt Construction (Minimal Pattern)

When using an agent, structure prompt like:

```
Context:
 - pipeline loop: lib/app/pipeline/recognition_pipeline.dart (lines ~1–180)
 - fusion rules: docs/features/todo/recognition_pipeline.md#confidence-fusion
Task:
 - Add unit test for dedupe boundary (event exactly at window limit)
Constraints:
 - No new deps; pure test only; keep file <150 lines
Output:
 - Single test file content
```

Do NOT paste whole large docs—link them.

---

## 9. Fast Reference Table (High-Value Docs)

| Topic | Path |
|-------|------|
| Architecture Overview | docs/architecture/overview.md |
| Pipeline Short | docs/architecture/pipeline.md |
| Domain Model | docs/data/domain_model.md |
| Persistence | docs/data/persistence.md |
| Model Adapters | docs/models/model_adapters.md |
| Testing Strategy | docs/dev/testing_strategy.md |
| Performance | docs/dev/performance.md |
| ADR Template | docs/architecture/adrs/ADR-000-template.md |

Keep this table updated if paths change.

---

## 10. Common Noise to Remove Quickly

- Stale TODOs (>30 days) without owner/date.
- Redundant examples already covered in README.
- Long inline pseudocode once real implementation exists (replace with “See implementation: <file>”).
- Large sample payloads—move to `test/fixtures/` and link.

---

## 11. Refactor Triggers (Context Reduction)

Refactor immediately when:
- A function exceeds ~60–70 LOC (split pure subroutines).
- A test file contains >12 distinct logical behaviors (break into themed files).
- Multiple unrelated concerns in one file (e.g., adapter + metrics formatting).

---

## 12. Minimal ADR Adoption Note

When implementing an ADR:
- Add single-line note in each touched module header:
  `// Implements ADR-0XX (<short-title>)`
- Update ADR with “Implemented: <commit hash>”.

---

## 13. Quick Checklist Before Invoking an Agent

[ ] Is there a smaller file or index I can link instead of pasting bulk text?  
[ ] Did I remove unrelated context lines from the prompt?  
[ ] Are all file paths relative & precise?  
[ ] Did I include constraints (size, purity, no new deps)?  
[ ] Did I specify exact desired output format?  

If any “No” → tighten prompt first.

---

## 14. Change Log

| Version | Summary |
|---------|---------|
| 0.2 | Rewritten minimal context-reduction focused guide |
| 0.1 | (superseded) Initial broad governance draft (removed) |