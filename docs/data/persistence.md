# Persistence (Short)

Links: [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]] • [[domain_model|Domain Model]] • [[../models/model_adapters|Model Adapters]] • [[../ui/features|UI Features]] • [[../dev/testing_strategy|Testing]] • [[../dev/performance|Performance]]
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

Legacy detailed content follows (to be trimmed). Core points:
- Tables: plates, recognitions, meta_kv
- Key indices: normalized plate; (plate_id, ts)
- Atomic ingest: lookup/create plate + insert recognition + update stats (one transaction)
- Migration: versioned, idempotent, foreign keys ON
- Performance: short transactions, prepared statements, WAL
- Privacy: local only, optional purge, no raw frames

(Replace remainder with concise sections in future commit.)

---

## 1. Purpose

Define how PlateRunner stores, retrieves, and evolves on-device data safely and efficiently while remaining offline-first and privacy-focused.

Goals:
- Fast lookup of normalized plates.
- Append-friendly recognition event logging.
- Predictable, reversible migrations.
- Resource efficiency (mobile constraints).
- Extensibility for future clustering, watchlists, analytics.

Non-Goals (initial):
- Cloud sync conflict resolution.
- Encrypted at-rest storage (may come later).
- Partitioned or sharded storage.

---

## 2. Storage Technology

Primary: SQLite (bundled with Flutter via a plugin—exact package TBD).  
Rationale:
- Mature, stable, mobile-optimized.
- Rich indexing & transaction semantics.
- Easy migration versioning.
- Low overhead, good for structured queries and constraints.

Future Option: SQLCipher integration for encryption.

---

## 3. High-Level Schema (Initial)

Tables (baseline set):

1. `plates`
2. `recognitions`
3. `meta_kv` (key/value store for migrations + simple config)
4. (Future) `watchlists`
5. (Future) `model_metrics`

---

## 4. Table Definitions (Proposed DDL v1)

(Actual DDL executed through migration system; final syntax may change.)

plates:
- id TEXT PRIMARY KEY
- normalized TEXT NOT NULL UNIQUE
- region TEXT NULL
- first_seen_ts INTEGER NOT NULL
- last_seen_ts INTEGER NOT NULL
- total_recognitions INTEGER NOT NULL DEFAULT 1
- user_label TEXT NULL
- notes TEXT NULL
- flags_json TEXT NULL              (serialized JSON)
- custom_fields_json TEXT NULL       (serialized JSON)
- last_modified_ts INTEGER NOT NULL  (epoch ms update trigger)
- version INTEGER NOT NULL DEFAULT 1 (for optimistic concurrency / future diff)

Indices:
- idx_plates_normalized (unique already by constraint, still explicit in some ORMs)
- idx_plates_last_seen_ts (descending - for recent queries)

recognitions:
- id INTEGER PRIMARY KEY AUTOINCREMENT
- plate_id TEXT NOT NULL REFERENCES plates(id) ON DELETE CASCADE
- ts INTEGER NOT NULL
- latitude REAL NULL
- longitude REAL NULL
- confidence REAL NOT NULL
- frame_ref TEXT NULL
- model_id TEXT NULL
- raw_text TEXT NULL
- processing_flags INTEGER NOT NULL DEFAULT 0
- inserted_ts INTEGER NOT NULL        (wall clock insertion time)

Indices:
- idx_recognitions_plate_ts (plate_id, ts DESC)
- idx_recognitions_ts (ts DESC)
- idx_recognitions_model (model_id)

meta_kv:
- key TEXT PRIMARY KEY
- value TEXT NOT NULL
- updated_ts INTEGER NOT NULL

Reserved keys:
- schema_version
- last_integrity_check_ts
- feature_flag_<name>

---

## 5. Data Access Patterns

| Use Case | Query Shape | Notes |
|----------|-------------|-------|
| Lookup plate by text | SELECT * FROM plates WHERE normalized=? | Must be O(log N) → unique index |
| Insert recognition event | INSERT into recognitions + update plates | Wrapped in single transaction |
| Most recent recognitions | SELECT ... ORDER BY ts DESC LIMIT K | Covering index on ts |
| Plate history scroll | SELECT ... WHERE plate_id=? ORDER BY ts DESC LIMIT ? OFFSET ? | Combined plate_id+ts index |
| Search partial (future) | LIKE / FTS virtual table (optional) | Might introduce FTS5 table |
| Recent unique plates | SELECT * ORDER BY last_seen_ts DESC LIMIT N | Index on last_seen_ts |

Potential optimization: Precompute small materialized view (or maintainable cache table) if “recent unique” queries become heavy—defer until measured.

---

## 6. Transaction Semantics

Atomic recognition ingestion:
1. Begin immediate transaction.
2. Lookup plate by normalized.
3. If absent: INSERT new plate (first_seen_ts = last_seen_ts = now).
4. INSERT recognition row.
5. UPDATE plates SET last_seen_ts=?, total_recognitions=total_recognitions+1, last_modified_ts=now WHERE id=?
6. Commit.

Retry logic:
- If UNIQUE(normalized) conflict lost race → re-query plate id then resume.
- Use small bounded retry (e.g., max 2 attempts).

All writes use WAL mode for better concurrent read performance.

---

## 7. Migration Strategy

Phases:
1. On app start: open DB / create if absent.
2. Read `schema_version` from `meta_kv` (if missing → version 0).
3. Apply ordered migration steps: `migrate_v0_to_v1`, `migrate_v1_to_v2`, ...
4. Each migration runs inside its own transaction; failure → rollback.
5. After success, update `schema_version`.

Migration File Conventions:
- Each migration code path idempotent (checks presence before create).
- No destructive column drops until deprecation period passes.
- For heavy transformations:
  - Create new shadow table
  - Copy, validate, swap, drop old
  - Vacuum if fragmentation > threshold.

Integrity post-check:
- Foreign keys pragma ON.
- Execute quick COUNT sanity on key tables.

---

## 8. Versioning Plan (Tentative Roadmap)

| Version | Changes |
|---------|---------|
| v1 | Base schema (plates, recognitions, meta_kv) |
| v2 | Add model performance table + index on confidence |
| v3 | Add watchlist table + trigger for alert counts |
| v4 | Introduce cluster summary table (optional compression) |

---

## 9. Data Retention & Compaction

Retention knobs (future user settings):
- Max recognition rows (rolling purge oldest beyond N).
- Purge by age (delete events older than X days).
- Manual “Clear History” action:
  - Delete from recognitions
  - Reset plate counts or delete plates with no user metadata.

Compaction:
- After large purge, optionally `VACUUM` outside UI-critical path (deferred to idle / background isolate).

---

## 10. Index Tuning Considerations

Potential Anti-Patterns:
- Over-indexing: insertion-heavy recognition events suffer.
- Expression indexes (e.g., on UPPER(normalized)) unnecessary if we normalize upstream.

Periodic Review Metrics:
- avg insertion latency
- page cache hit ratio
- table & index size growth
- top query EXPLAIN output stored for regression analysis (dev mode only)

---

## 11. Concurrency & Isolation

SQLite on mobile: single-writer, multi-reader.
Mitigations:
- Keep write transactions short (< 10ms).
- Pre-prepare statements.
- Avoid long-running SELECTs without pagination.
- For analytics (future): run on read replica (copy) or windowed queries.

---

## 12. Error Handling & Recovery

Categories:
- Corruption (SQLite returns error code) → escalate; offer user remediation (“Reinitialize Database”).
- Busy/locked → apply small backoff & retry (ex: exponential up to 3 tries).
- Migration failure → rollback & surface blocking error; do not proceed with partial schema.

Recovery:
- Keep a lightweight export (JSON) for user plate + metadata on user action (optional).
- On failure to open DB: attempt backup file rename, recreate fresh DB.

---

## 13. Data Integrity Checks

Scheduled (dev / optional prod):
- COUNT(*) consistency between `plates.total_recognitions` and actual event counts sample.
- Random sample validation: last_seen_ts equals MAX(recognitions.ts).
- Foreign key PRAGMA integrity_check.

If discrepancy found:
- Log structured issue
- Optionally self-heal (recompute counters).

---

## 14. Deletion & Privacy

Delete Strategies:
- Soft delete not used initially (physical delete).
- Plate deletion (user initiated):
  - DELETE FROM recognitions WHERE plate_id=?
  - DELETE FROM plates WHERE id=?
  - VACUUM optional (deferred).

Secure delete:
- SQLite `PRAGMA secure_delete = ON` (optional performance trade-off).

---

## 15. Performance Guidelines

Insertion Batch:
- If multiple recognition events produced in same inference cycle, group writes in a single transaction.

Prepared Statements:
- Cache for:
  - Plate lookup by normalized
  - Insert recognition
  - Update plate stats
  - Recent recognitions query

Avoid:
- SELECT * for high-frequency queries; project only required columns.

---

## 16. Future Enhancements

| Feature | Persistence Impact |
|---------|--------------------|
| Recognition Clustering | New table or materialized view; may reduce events volume |
| Watchlists | New table + index on normalized or plate_id |
| Tagging / Classification | Add `tags_json` or separate join table |
| Full Text Search | FTS5 virtual table for notes / user_label |
| Encryption | Wrap open with key; migrate existing plain DB |
| Differential Sync | Tombstone columns + change feed table |
| Model Telemetry | model_metrics table (model_id, avg_latency_ms, last_loaded_ts) |

---

## 17. Testing Strategy (Persistence Layer)

Test Classes:
- MigrationTests: Start from v0 baseline DB file → run incremental upgrades → assert schema & data transformation.
- ForeignKeyTests: Attempt invalid inserts expect failure.
- PerformanceSmokeTests: Insert 10k synthetic recognitions; assert time budget.
- IntegrityRecomputeTests: Tamper plate counts → run recompute → validate correction.

Test Data Patterns:
- Plate with high churn (many rapid events).
- Plates differing by single ambiguous character (O vs 0).
- Events missing geo data vs present.

---

## 18. Sample Pseudocode (Insertion Flow)

(Conceptual, not final.)

function ingestRecognition(normalizedPlate, eventData):
  begin transaction
    plate = selectPlate(normalizedPlate)
    now = epochMs()
    if plate == null:
       id = uuid()
       insertPlate(id, normalizedPlate, firstSeen=now, lastSeen=now)
    else:
       id = plate.id
    insertRecognition(
       plate_id = id,
       ts = eventData.ts,
       latitude = eventData.lat,
       longitude = eventData.lon,
       confidence = eventData.conf,
       frame_ref = eventData.frameRef,
       model_id = eventData.modelId,
       raw_text = eventData.rawText,
       processing_flags = eventData.flags,
       inserted_ts = now
    )
    update plates
       set last_seen_ts = max(last_seen_ts, eventData.ts),
           total_recognitions = total_recognitions + 1,
           last_modified_ts = now
       where id = id
  commit

---

## 19. Metrics (Optional Future)

Collected (dev mode):
- avg insertion latency (ms)
- P95 recognition query latency
- DB size (MB)
- Row counts (plates, recognitions)
- Failure codes distribution

Store ephemeral metrics in memory; persist to model_metrics or meta_kv only if needed.

---

## 20. Open Questions

| ID | Question | Notes |
|----|----------|-------|
| PQ-01 | Use natural key (normalized) as PK for plates? | Leaning surrogate to allow future merges |
| PQ-02 | Add event partitioning by month? | Not until > ~100k rows observed |
| PQ-03 | Secure delete default ON? | Performance measurement required |
| PQ-04 | FTS for notes? | Post-MVP after user metadata adoption |
| PQ-05 | Region inference caching? | Could add region column update after background detection |

---

## 21. Change Log

| Version | Summary |
|---------|---------|
| 0.1 | Initial persistence draft spec |

---

End of document (v0.1)