# Feature TODO: Runtime Config Persistence

Status: Draft (v0.1)  
Owner: (assign)  
Related: ../architecture/overview.md • ../architecture/pipeline.md • ../dev/testing_strategy.md
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

---

## 1. Goal

Persist `RuntimeConfig` (see `lib/shared/config/runtime_config.dart`) across app launches so user / system adjustments (e.g., sampling interval, active model, dev overlay toggle) survive restarts and can be restored early during boot.

---

## 2. Scope (MVP)

In-scope (Phase 1):
- Local **key–value** persistence of full `RuntimeConfig` snapshot.
- Single namespace (no multi-profile / environment layering).
- Load persisted snapshot before first `MaterialApp` build (best‑effort).
- Graceful fallback to defaults if corrupted / missing.
- Simple versioning to handle added/removed fields.

Deferred (Later Phases):
- Remote sync / feature flag platform integration.
- Partial diff storage.
- Cryptographic signing / tamper detection.
- Multi-tenant profiles.
- Live migration UI.

---

## 3. Non-Goals

- Complex schema migrations (KV + JSON only).
- Encrypted storage (not needed for non-sensitive tunables).
- Real-time multi-process coordination (single isolate context only).

---

## 4. Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| RC-PERSIST-01 | Persist latest committed config snapshot on update() | Must |
| RC-PERSIST-02 | Attempt load once during bootstrap before `runApp` | Must |
| RC-PERSIST-03 | Validate JSON; fall back to defaults on parse error | Must |
| RC-PERSIST-04 | Backwards-compatible when fields added | Must |
| RC-PERSIST-05 | Expose async `initialize()` returning loaded config | Must |
| RC-PERSIST-06 | Write operations debounced to avoid flash writes | Should |
| RC-PERSIST-07 | Provide manual `export()` / `import()` hooks (future) | Could |
| RC-PERSIST-08 | Record load source (default vs persisted) for logging | Should |
| RC-PERSIST-09 | Unit tests for corruption, partial fields, new fields | Must |

---

## 5. Data Model

Represent persisted snapshot as JSON:
```
{
  "version": 1,
  "payload": {
     // keys mirroring serializeConfig()
     "minFusedConfidence": 0.55,
     ...
     "featureFlags": { ... }
  },
  "tsSaved": 1711111111111
}
```

Rationale:
- Explicit wrapper enables format evolution.
- `version` allows future structural change without ambiguity.

---

## 6. Storage Options (Evaluate)

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| SharedPreferences | Simple, available | String size limit risk (low) | Accept (MVP) |
| Local file (app dir) | Full control | More IO boilerplate | Alternate |
| SQLite meta table | Stronger migration control | Overkill for single JSON | No (MVP) |

Decision: Use `SharedPreferences` under key: `runtime_config.snapshot.v1`.

Fallback: If value length > safe threshold (~32KB) (unlikely) log warning & skip.

---

## 7. Service Layer Extension

Introduce `PersistedRuntimeConfigService` that decorates / composes existing `InMemoryRuntimeConfigService`:

Interface additions:
```
abstract interface class PersistentRuntimeConfigBoot {
  Future<RuntimeConfig> loadOrDefault();
  Future<void> dispose();
}
```

Workflow:
1. At bootstrap, call `PersistentRuntimeConfigBoot.loadOrDefault()`.
2. Seed `InMemoryRuntimeConfigService.seed(loadedConfig)`.
3. Wrap updates: subscribe to `updates` stream → debounce (e.g., 250ms) → persist latest snapshot.

---

## 8. Initialization Sequence

Pseudocode:
```
WidgetsFlutterBinding.ensureInitialized();
final boot = SharedPrefsRuntimeConfigBoot();
final cfg = await boot.loadOrDefault();
final svc = InMemoryRuntimeConfigService.seed(cfg);
runApp(PlateRunnerApp(configService: svc));
```

Edge case: If load fails (throws), log & proceed with defaults.

---

## 9. Versioning & Forward Compatibility

Strategy:
- When reading: ignore unknown top-level keys inside `payload`.
- Missing expected keys → rely on `deserializeConfig` fallback (already merges defaults).
- If `version` unsupported: treat as incompatible → discard & log `config_persist_version_mismatch`.

Future upgrade path:
- Add `migrations/{n}_to_{n+1}.dart` if structure changes beyond additive.

---

## 10. Persistence Trigger & Debounce

Trigger on:
- `update()` successful commit
- `replace()`
- `reset()`

Debounce reasoning:
- Rapid slider adjustments (e.g., confidence) could cause write spam.
- Use simple timer: schedule write 250ms after last change; coalesce intermediate.

---

## 11. Failure Handling

| Scenario | Handling |
|----------|----------|
| SharedPreferences unavailable | Log `[CONFIG] persist_unavailable` once; continue in-memory |
| JSON parse error | Log `[CONFIG] persist_corrupt` with length; delete key; use defaults |
| Write failure (exception) | Log `[CONFIG] persist_write_error`; next update tries again |
| Disposal pending while write queued | Flush immediately before `dispose()` |

No user-facing UI for errors (MVP); internal logging only.

---

## 12. Logging Conventions

Structured log tags:
- `[CONFIG] persist_loaded source=default|store version=N`
- `[CONFIG] persist_saved sizeBytes=X elapsedMs=Y`
- `[CONFIG] persist_corrupt len=X`
- `[CONFIG] persist_write_error error=...`

Metrics (future):
- config.persist.load.latency.ms
- config.persist.snapshot.bytes

---

## 13. Security & Privacy

- No sensitive keys; JSON not encrypted.
- Ensure feature flags do not store PII (enforce at flag assignment review).
- Potential future: add checksum if tamper detection required.

---

## 14. Test Plan

Unit:
- Load with complete valid snapshot.
- Load with missing fields → defaults merged.
- Corrupted JSON (truncated / invalid) → fallback + log.
- Unknown version number.
- Debounce: multiple rapid updates triggers single write.
- Feature flags merge behavior.

Integration (instrumented):
- Simulate cold start with previously saved config.
- Simulate concurrent rapid updates (stress) - ensure final state persisted.

Mutation Tests (optional later):
- Remove required key and assert safe fallback.

---

## 15. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Silent write failures → stale config | Confusing user expectation | Structured error logs + optional telemetry hook |
| Large featureFlags map growth | Storage bloat | (Later) enforce max key count or byte size |
| Race: read before write complete at boot | Inconsistent UI | Boot sequence ensures read completed before runApp |
| JSON key rename without migration | Loss of prior values | Maintain backward-compatible field names; additive only until major rev |

---

## 16. Implementation Steps (Phased)

Phase 1 (MVP):
1. Add `shared/config/persistence/` directory.
2. Implement `SharedPrefsRuntimeConfigBoot`.
3. Wire bootstrap in `main.dart` (async main).
4. Subscribe to `updates` with debounce + persist.
5. Add logging & basic unit tests.

Phase 2 (Hardening):
6. Add metrics counters (if metrics infra ready).
7. Add manual `forceSave()` for test harness.
8. Add export/import (debug only).

Phase 3 (Optional Enhancements):
9. Add checksum & size guard.
10. Add key eviction policy for flags.

---

## 17. Open Questions

| ID | Question | Status |
|----|----------|--------|
| RC-PQ-01 | Need explicit user "reset to defaults" UI? | TBD |
| RC-PQ-02 | Introduce encryption early? | Probably no (MVP) |
| RC-PQ-03 | Persist partial deltas vs full snapshot? | Over-optimization now |
| RC-PQ-04 | Support environment layering (dev/prod)? | Use separate builds instead |

---

## 18. Future Extensions

- Remote override layer (download JSON delta, merge with local).
- Policy engine for validating values (range, inter-field constraints).
- Observability panel showing current persistence load status & last saved timestamp.
- Multi-profile (e.g., "High Performance", "Battery Saver") quick switching.

---

## 19. Definition of Done (Phase 1)

- On cold start after modifying a config value, the changed value survives restart.
- All unit tests passing (including corruption, missing fields cases).
- No uncaught exceptions during load/save under normal flows.
- Logs visible for load & save paths.
- Debounce verified (only 1 persisted snapshot for burst of ≥5 updates in 300ms window).
- Document updated (this file) with final version tag.

---

## 20. Example Snippet (Conceptual)

```
class SharedPrefsRuntimeConfigBoot implements PersistentRuntimeConfigBoot {
  static const _kKey = 'runtime_config.snapshot.v1';

  Future<RuntimeConfig> loadOrDefault() async {
     final prefs = await SharedPreferences.getInstance();
     final raw = prefs.getString(_kKey);
     if (raw == null) return RuntimeConfig.build();
     try {
        final map = jsonDecode(raw) as Map<String, Object?>;
        final payload = map['payload'];
        if (payload is Map<String, Object?>) {
           return deserializeConfig(payload);
        }
     } catch (_) { /* log corrupt */ }
     return RuntimeConfig.build();
  }

  Future<void> persist(RuntimeConfig cfg) async { /* debounced write */ }
}
```

(Real code will live under `lib/shared/config/persistence/`.)

---

## 21. Change Log

| Version | Notes |
|---------|-------|
| 0.1 | Initial draft |

---

End of document.