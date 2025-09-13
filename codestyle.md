# Code Style (PlateRunner)

Concise conventions for a fast, consistent codebase. Complements [[docs/architecture/overview|Architecture]], [[docs/architecture/pipeline|Pipeline]], [[docs/dev/testing_strategy|Testing]], [[docs/dev/performance|Performance]].

---

## 1. Philosophy
Functional Core (pure, deterministic) + Imperative Shell (IO, orchestration). Prefer immutability, clarity over cleverness, explicit over implicit.

---

## 2. Directory Conventions
lib/
- domain/  Pure value objects & pure functions only.
- app/     Use cases (imperative orchestration).
- features/<feature_name>/ UI + controllers for that feature.
- infrastructure/ Platform + DB + model adapters.
- shared/  Cross-cutting small utilities (avoid dumping ground).
- ui/      Theming + generic widgets (not feature specific).

No circular imports. Domain never imports infrastructure or features.

---

## 3. Naming
Classes: PascalCase (`PlateRecord`, `RecognitionEvent`).
Files: snake_case (`plate_record.dart`).
Private helpers: leading underscore.
Boolean vars: positive form (`isActive`, `hasGeo`).
Async functions: verb + context (`loadModel()`, `ingestFrame()`).

Avoid abbreviations unless standard (GPS, ID, DB).

---

## 4. Pure vs Impure
Pure (domain/*):
- No side effects.
- No logging.
- Return data or Result types.
Imperative (app/, infrastructure/):
- Wrap side effects.
- Convert external failures → domain-safe errors.

Never pull platform channels into domain.

---

## 5. Data & Immutability
Use `const` & `final` aggressively.
Value objects: provide `copyWith()` only if needed.
Expose unmodifiable views for lists/maps.
Avoid mutable static state.

---

## 6. Error Handling
Domain functions return:
- `Either<DomainError, Value>` or nullable only if semantically “absence”.
Avoid throwing in domain except for truly unrecoverable programmer errors (asserts in debug).
Translate infra exceptions at boundary (e.g. `SqliteException` → `PersistenceError`).

---

## 7. Null-Safety
Prefer explicit Option/Either patterns to cascades of `!`.
Public API surfaces avoid returning `null` collections—use empty lists/maps.

---

## 8. Logging
Tag-based structured strings:
`[PIPELINE] recognition_persisted plate=ABC123 conf=0.87 latencyMs=78`
No logging in tight inner loops unless dev flag enabled.
Never log raw frame data.

---

## 9. Configuration
All tunables behind a config service (in `shared/config/`).
No magic numbers in code paths—pull from config constants (see [[docs/dev/performance|Performance]]).
Environment flags via `--dart-define` funneled through a single adapter.

---

## 10. Model Adapters
Follow contract in [[docs/models/model_adapters|Model Adapters]].
No UI imports.
Do not retain Frame objects longer than inference duration.
Reuse buffers; avoid per-call allocations > 8 KB.

---

## 11. UI / State
Feature controllers (if Riverpod chosen): one provider per responsibility, granular.
UI components: pure where possible; no business logic (delegate to controller/use case).
Avoid passing raw entities deep—map to lightweight view models.

---

## 12. Tests (See [[docs/dev/testing_strategy|Testing]])
Pure functions: unit tests (no mocks).
Adapters: contract tests + failure injection.
Pipeline: deterministic scenario replay (fixture → expected hash).
UI: widget tests for interactions; minimal golden snapshots.

---

## 13. Performance
Before optimizing, capture baseline metrics (timing spans or harness).
No micro-optimizing readability away without a measured win.
Watch allocation churn in high-frequency paths (sampling, inference loop).

---

## 14. Comments & Docs
Comment “why”, not “what” when code is non-obvious.
Top-of-file doc comment for public entrypoints/export barrels.
Keep TODOs actionable: `TODO(username, yyyy-mm-dd): reason`.
Add a backlink snippet (see top) to new substantive docs so the graph stays connected; add the doc to README + main index categories when created.

---

## 15. Commit Messages
Format:
`<scope>: <concise imperative>`
Examples:
`domain: add confidence fusion penalty for glare`
`pipeline: implement dedupe time+geo window`
Reference issue/ADR where helpful.

---

## 16. Linting & Style Rules
Follow Dart recommended lints; treat warnings as errors.
Max line length: 100 (wrap early for readability).
Prefer small files (<400 lines). Split when:
- Multiple domain concepts.
- Mixed responsibilities emerging.

---

## 17. Dependency Hygiene
No direct feature → feature imports (use shared domain/use case abstraction if needed).
Limit third-party packages; justify additions in an ADR or inline rationale.
Wrap external APIs in adapters for testability.

---

## 18. Result Types (Lightweight Pattern)
Use sealed classes / enums or a small `Result<T,E>` pattern:
```
Success(value) | Failure(error)
```
Avoid returning booleans when richer context needed.

---

## 19. Style Anti-Patterns (Avoid)
- God service / manager classes.
- Static global mutable singletons.
- Sprinkling async delays in tests (use controlled clocks).
- Overusing `dynamic` / `var` when type adds clarity.
- Silent catch blocks (`catch {}`).

---

## 20. Review Checklist (Author Self-Check)
- Pure logic isolated?
- Names descriptive and consistent?
- Any side effects inside domain? (Fix)
- Config values centralized?
- Tests cover new branches?
- Logging concise & structured?
- No unnecessary allocations in hot path?

---

## 21. Updates
Keep this file short—link deeper rationale to other docs. Major deviations require ADR (link from [[docs/architecture/overview|Architecture]] ADR section).

---

## Change Log
1.1 Added backlink snippet + cross-link guidance section updates.
1.0 Initial concise code style guide.