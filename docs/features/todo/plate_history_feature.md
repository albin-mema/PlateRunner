# Feature TODO: Plate History & Detail Feature

Status: Draft (v0.1)  
Owner: (assign)  
Related Docs: recognition_pipeline.md • dev_overlay_ui.md • ../architecture/overview.md • ../architecture/pipeline.md • ../data/domain_model.md • runtime_config_persistence.md
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

---

## 1. Goal

Provide a user-facing feature to browse previously recognized license plates, view aggregated stats (first seen, last seen, counts, confidence trends), drill into recognition event timelines, and support future extensions (filters, search, tagging). Must be lightweight, performant on modest datasets (hundreds–low thousands of records), and respect privacy principles (no raw frame imagery persisted in MVP).

---

## 2. Scope (MVP)

In-Scope (Phase 1):
- Plate History screen (list of plates sorted by last seen desc).
- Plate Detail screen (stats + recent recognition events list).
- Basic search/filter by normalized plate substring (client-side).
- Display key metrics: firstSeen, lastSeen, totalRecognitions, highestConfidence, averageConfidence (computed / cached), lastConfidence, streak (optional).
- Pagination / incremental loading (lazy list) for large sets.
- Simple empty state & no-results state.
- Delete all history (global purge) action (confirmation).
- Plate-level delete (remove a single plate + its events).

Deferred (Later):
- Tagging / starring plates.
- Export / share recognized list.
- Confidence trend charts.
- Region / jurisdiction inference & grouping.
- Watchlist matching indicators.
- Geospatial clustering or mapping.
- Server/cloud sync.
- Photos / cropped thumbnails (no frame imagery in MVP).

---

## 3. Non-Goals

- Persisting raw image snippets or video frames (privacy / storage).
- Real-time collaboration / sync.
- Advanced full-text fuzzy search.
- Complex analytics dashboards.
- Role-based access or authentication.

---

## 4. User Stories (MVP)

| ID | Story | Priority |
|----|-------|----------|
| HIST-01 | As a user, I can see a list of recently recognized plates | Must |
| HIST-02 | As a user, I can tap a plate to view detailed stats | Must |
| HIST-03 | As a user, I can search plates by substring | Should |
| HIST-04 | As a user, I can refresh / auto-update when new recognitions occur | Must |
| HIST-05 | As a user, I can clear all recognition data | Should |
| HIST-06 | As a user, I can remove an individual plate from history | Could |
| HIST-07 | As a user, I can see last seen timestamp & count at a glance | Must |
| HIST-08 | As a user, I can understand confidence quality (e.g., high vs low) | Should |

---

## 5. Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-PLATE-01 | Provide paginated plate list sorted by lastSeen desc | Must |
| FR-PLATE-02 | Stream updates when new recognition affects list order | Must |
| FR-PLATE-03 | Fetch plate detail snapshot + latest N events | Must |
| FR-PLATE-04 | Compute derived stats (avgConfidence, maxConfidence) efficiently | Must |
| FR-PLATE-05 | Support substring search filtering (case-insensitive) | Should |
| FR-PLATE-06 | Provide delete(plateKey) cascading to recognition events | Could |
| FR-PLATE-07 | Provide purgeAll() operation (atomic) | Should |
| FR-PLATE-08 | Guard destructive actions with confirmation surface | Must |
| FR-PLATE-09 | Handle empty DB state gracefully | Must |
| FR-PLATE-10 | Respect runtime config for recentPlatesLimit if applicable | Should |
| FR-PLATE-11 | Avoid blocking UI thread for DB queries (async) | Must |

---

## 6. Domain / Data Model (Refinements)

Existing conceptual types (Plate, RecognitionEvent). For history:

Add (if not already):
```
PlateStats {
  DateTime firstSeen;
  DateTime lastSeen;
  int totalEvents;
  double maxConfidence;
  double avgConfidence;          // consider scaled integer storage
  int distinctDaysSeen;          // optional extension
}
```

For queries:
- `PlateHistoryEntry` (view DTO)
```
PlateHistoryEntry {
  String plateKey;
  DateTime lastSeen;
  int totalEvents;
  double maxConfidence;
  double lastConfidence;
  double avgConfidence;
}
```

Plate Detail:
```
PlateDetail {
  PlateHistoryEntry summary;
  List<RecognitionEventListItem> recentEvents; // limited N
}
RecognitionEventListItem {
  DateTime ts;
  double confidence;
  int qualityFlags;
  // optional: modelId, inferenceLatencyMs (future)
}
```

---

## 7. Persistence Considerations

Tables (assumed):
- `plates` (plate_key PK, first_seen, last_seen, event_count, max_confidence, avg_conf_scaled, ...)
- `recognitions` (id PK, plate_key FK, ts, confidence, quality_flags, model_id, ...)

For avgConfidence:
- Store scaled integer (e.g., confidence * 1000) to minimize FP drift, updated incrementally.

Incremental update formula:
```
newAvg = ((oldAvg * (count - 1)) + newConfidence) / count
```

Indices:
- `plates(last_seen DESC)` for list ordering.
- `recognitions(plate_key, ts DESC)` for detail retrieval.

---

## 8. Query Patterns

1. Paginated plate list:
```
SELECT plate_key, last_seen, event_count, max_confidence, last_confidence, avg_conf_scaled
FROM plates
ORDER BY last_seen DESC
LIMIT ? OFFSET ?;
```

2. Substring search (normalized):
```
... WHERE plate_key LIKE '%ABC%' COLLATE NOCASE ORDER BY last_seen DESC LIMIT ...
```
(Consider parameter sanitization; ensure wildcard use safe.)

3. Recent events for plate:
```
SELECT ts, confidence, quality_flags
FROM recognitions
WHERE plate_key = ?
ORDER BY ts DESC
LIMIT N;
```

---

## 9. Performance Targets

| Aspect | Target |
|--------|--------|
| Plate list query (page size 50) | < 25 ms |
| Plate detail + 20 events | < 30 ms |
| Search filter latency | < 75 ms for ≤ 2k plates |
| UI frame jank introduced | None (queries async) |
| Purge operation | < 250 ms for ≤ 10k events (blocking splash/progress) |

---

## 10. Caching Strategy

- In-memory LRU for last X `PlateHistoryEntry` objects (configurable future).
- Real-time incremental update path: when pipeline persists event, push delta to history controller (bypass full DB re-query for top-of-list reorder).
- Invalidate / refresh if search active (apply filter client-side if data subset loaded).

---

## 11. UI / UX Overview

Screens:
1. History Screen
   - AppBar: "History"
   - Search field (debounced 250 ms)
   - List items: Plate text, lastSeen relative (e.g., "2m ago"), totalEvents, lastConfidence badge (color-coded).
   - Pull-to-refresh (optional; though live stream auto-updates).
   - Empty state: "No recognitions yet. Start scanning to build history."

2. Plate Detail Screen
   - Header: Plate text large + key stats (count, first/last).
   - Confidence metrics row (avg, max, last).
   - Recent events list with timestamp & confidence + quality indicators.
   - Actions menu: Delete Plate (if enabled), Export (future), Back.

Design Tokens:
- Reuse theme spacing & typography (no custom ad‑hoc pixel values).
- Confidence color:
  - >=0.80 : success/green tone
  - 0.60–0.79 : amber
  - <0.60 : warning/red

---

## 12. State Management

Controllers (feature-local):
```
PlateHistoryController {
  Stream<HistoryViewState> states;
  Future<void> loadInitial({int pageSize});
  Future<void> loadNextPage();
  void applySearch(String query); // debounced
  void onRecognitionDelta(RecognitionDelta delta); // from pipeline
  Future<void> deletePlate(String plateKey);
  Future<void> purgeAll();
  void dispose();
}
```

`RecognitionDelta`:
```
RecognitionDelta {
  String plateKey;
  DateTime ts;
  double confidence;
  bool isNewPlate;
}
```

Plate Detail Controller:
```
PlateDetailController {
  Future<void> load(String plateKey);
  Stream<PlateDetailState> state;
  void dispose();
}
```

Avoid direct DB calls inside widgets; controllers map repository futures/streams into view states.

---

## 13. Runtime Config Integration

Fields considered:
- `recentPlatesLimit` (caps maximum tracked plates if needed).
- `maxRecentEventsWindowPerPlate` (limit events list in detail if applying caching).
- Feature flag possibility: `flags['history.search.enabled']` (optional gating).
- Dev overlay synergy: clicking last recognition could deep-link into detail (future).

No config writes originate from history feature.

---

## 14. Logging (Structured)

Component `history` events:
- `history_load_page` { page, size, ms }
- `history_search` { queryLength, ms, resultCount }
- `history_delta_applied` { plate, isNew }
- `history_plate_delete` { plate, eventsRemoved }
- `history_purge_all` { plates, events, ms }
- `history_detail_load` { plate, ms, eventCount }

Respect verbosity: if `enableVerbosePipelineLogs=false`, throttle high-frequency search logs (sample).

---

## 15. Error Handling

| Failure | Handling |
|---------|----------|
| DB query error | Emit error state + retry action; log event |
| Purge failure partial | Rollback transaction if atomic; user sees error banner |
| Delete plate FK constraints | Ensure cascading or explicit transaction sequence |
| Large search input performance degradation | Debounce & early return if unchanged |
| Memory pressure w/ large in-memory caches | Provide optional size clamps |

User-facing errors: brief snackbar / banner; core pipeline unaffected.

---

## 16. Privacy & Security

- No raw frame or PII beyond plate alphanumeric string.
- Provide potential config future: mask middle characters in UI for demonstration mode.
- Purge must fully remove associated recognition events (verify cascade).

---

## 17. Testing Strategy

Unit:
- Incremental delta application ordering (when new lastSeen supersedes top).
- Search filtering correctness (case-insensitive).
- Pagination boundary conditions (no duplication / overlap).
- Average confidence incremental update accuracy (floating tolerance).
- Delete & purge state transitions.

Repository Mock / Contract Tests:
- Simulate DB returning defined sets; assert controller states sequence.

Performance (Synthetic):
- Generate 2000 plates with varied lastSeen; measure search filter latency (< target).
- Simulate 500 recognition deltas; ensure no O(N) scans degrade performance (optimize with map lookups).

Widget Tests:
- History list renders items & updates on controller stream emit.
- Search field input shows filtered subset.
- Plate detail displays stats & events list sorted.

Edge Cases:
- All events for a plate below confidence threshold? (Never persisted by pipeline, so not represented.)
- Very large counts formatting (1,250 -> "1.2K" maybe future; MVP plain).

---

## 18. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Large dataset slow pagination | UI jank | LIMIT/OFFSET + indexing |
| Search over large set O(N) expensive | Stutters | Debounce + maybe pre-lowercased key cache |
| Delta reorder logic inconsistency | List flicker | Stable keyed list diff |
| Purge accidental | Data loss | Confirmation modal (double confirm?) |
| Floating precision drift avgConfidence | Incorrect stats | Use scaled integers |
| Event storms reorder thrash | Frequent rebuilds | Batch deltas (coalesce microtasks) |

---

## 19. Implementation Phases

Phase 1 (Data & Controllers):
1. Extend repositories: plate list query, plate detail, delete, purge.
2. Implement history controller with pagination + delta handling.
3. Implement detail controller.

Phase 2 (UI):
4. Build History screen (list + search).
5. Build Plate Detail screen.
6. Wire recognition pipeline delta emission (observer / stream).

Phase 3 (Enhancements):
7. Add delete plate & purge actions.
8. Confidence color coding & formatting utilities.
9. Logging & metrics instrumentation.

Phase 4 (Polish & Tests):
10. Unit tests (controllers / logic).
11. Widget tests & performance smoke test.
12. Documentation updates & finalize DoD checklist.

---

## 20. Integration with Pipeline

Pipeline after persistence can emit:
```
RecognitionDelta(
  plateKey: normalized,
  ts: detectionTs,
  confidence: fusedConfidence,
  isNewPlate: persistedPlateWasCreated
)
```
History controller subscribes and updates in-memory view model quickly (then optionally schedules background fetch to keep metrics exact if approximations used).

---

## 21. UI Data Formatting

Guidelines:
- Relative time < 24h: "5m ago", "2h ago".
- Confidence: fixed 2 decimals (0.87) or percent "87%"; choose consistent (use raw decimal like other docs).
- Large counts optional: plain integer MVP.

Utility functions centralized in `shared/format/formatters.dart` (future stub) to avoid duplication.

---

## 22. Open Questions

| ID | Question | Status |
|----|----------|--------|
| HIST-PQ-01 | Store recognition events indefinitely or apply retention policy? | Defaults unlimited (config purgeRetentionDays=0) |
| HIST-PQ-02 | Should purge reuse existing retention logic path? | Likely yes (shared purge function) |
| HIST-PQ-03 | Support multi-sort (by count, confidence)? | Future toggle |
| HIST-PQ-04 | Add watchlist marker column early? | Post-MVP |
| HIST-PQ-05 | Limit max local events for memory reasons? | Possibly config-based later |

---

## 23. Definition of Done (MVP)

- History list loads, paginates, and reorders on new recognitions without manual refresh.
- Plate detail screen shows accurate stats (validated by test fixtures).
- Search functional & responsive on dataset of ≥ 1000 plates.
- Delete single plate removes it & its events; list updates.
- Purge all empties list & emits correct state.
- Logging events recorded for major actions.
- All controller unit tests & widget tests pass.
- No frame drops during 500-delta burst simulation.
- Documentation (this file) updated with final version & OWNER assigned.

---

## 24. Task Checklist

- [ ] Repository extensions (list, detail, delete, purge).
- [ ] Add avgConfidence incremental update logic & scaled storage.
- [ ] Implement `PlateHistoryController`.
- [ ] Implement `PlateDetailController`.
- [ ] Wire pipeline delta emission.
- [ ] History screen UI + item widget.
- [ ] Search bar w/ debounce.
- [ ] Detail screen UI + events list.
- [ ] Confidence color badges utility.
- [ ] Delete plate action path.
- [ ] Purge all path (confirmation dialog).
- [ ] Logging integration.
- [ ] Unit tests: controllers (pagination, update, search).
- [ ] Widget tests: list & detail.
- [ ] Synthetic performance test harness.
- [ ] Update docs cross-links.
- [ ] Assign owner & finalize version.

---

## 25. Future Enhancements (Post-MVP)

- Tag / categorize plates (favorite, watchlist).
- Confidence trend sparkline.
- Export / share recognized plates (CSV / JSON).
- Filter: date range, confidence threshold.
- Background retention pruning job (rolling window).
- Local differential search index for fuzzy matching.
- Integration with dev overlay deep-link.

---

## 26. Change Log

| Version | Notes |
|---------|-------|
| 0.1 | Initial draft of Plate History & Detail feature spec |

---

End of document (v0.1).