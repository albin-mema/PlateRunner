# UI Features (Short)

Links: [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]] • [[../data/domain_model|Domain Model]] • [[../data/persistence|Persistence]] • [[../models/model_adapters|Model Adapters]] • [[../dev/testing_strategy|Testing]] • [[../dev/performance|Performance]]
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

## Feature List
| ID | Feature | Screen | Goal | Status |
|----|---------|--------|------|--------|
| FEAT-LIVE-SCAN | Live Scan | LiveScan | Real-time plate overlay | Planned |
| FEAT-DETAIL | Plate Detail | PlateDetail | Inspect + edit metadata | Planned |
| FEAT-HISTORY | History | History | Browse recognitions | Planned |
| FEAT-SEARCH | Search | Search | Quick plate lookup | Planned |
| FEAT-SETTINGS | Settings | Settings | Model & perf config | Planned |
| FEAT-NOTES | Notes / Tags | PlateDetail | Enrich plate | Planned |
| FEAT-PURGE | Clear Data | Settings | Privacy purge | Planned |
| FEAT-DEV-OVERLAY | Dev Overlay | LiveScan (dev) | Metrics debug | Planned |

## Screen Map
LiveScan → (tap plate) → PlateDetail  
LiveScan → History / Search / Settings  
History → PlateDetail  
Search → PlateDetail  
Settings → (Model dialog / Purge confirm)

## Layering
UI (widgets) → Controllers / Use Cases → Domain (pure) → Infra (db, model, camera). Domain never imports UI.

## Live Scan (Essentials)
- Camera preview + bounding boxes
- Recent strip (last N plates)
- Status icons: model, pipeline state, GPS
- Dev overlay (latency, FPS) in dev builds only

## Plate Detail
Header (plate + counts) • Recent events list (paged) • Notes/Tags (inline edit)

## History
Infinite scroll by newest; minimal row: plate, last seen, count, flags.

## Search
Normalize as user types; prefix match list → tap to navigate; “no match” hint.

## Settings
Sections: Model, Recognition (confidence, dedup ms, sampling), Data (purge), About.  
Danger actions isolated at bottom.

## Dev Overlay (Dev Only)
FPS (intake/processed), inference p95, dedupe ratio, queue depth, last plate/conf. Toggle in settings or secret tap.

## UX Principles
Uncluttered live screen • Immediate feedback • Non-blocking errors • Privacy-respectful • Accessible (contrast, labels).

## Performance Notes
Avoid rebuild storms; painter for overlays; pre-format times; buffer reuse in controllers.

## Open Questions
State mgmt choice (Riverpod?) • Confidence color thresholds source • Watchlist priority • Dark mode theming scope.

## Change Log
0.2 Short form with Obsidian links.

## 18. Error & Empty States Inventory

| Context | Empty State Copy | Action |
|---------|------------------|--------|
| History (no data) | “No recognitions yet” | Show hint: “Start scanning to build history” |
| Search (no matches) | “No matching plates” | Suggest: “Check spelling or scan new plate” |
| Plate Detail (deleted) | “Plate not found” | Back to history |
| Model Load Failure | “Model failed to load” | Retry / Select different model |
| Permissions Missing (camera) | “Camera access required” | Button: “Grant Permission” |
| Purge Complete | “History cleared” | Dismissible snackbar |

---

## 19. Logging Hooks (UI Layer)

Structured events (conceptual):
- `ui.nav.route_changed`
- `ui.live_scan.tap_plate`
- `ui.settings.change_model`
- `ui.settings.update_config`
- `ui.purge.confirmed`
- `ui.search.query_submitted`
- `ui.dev_overlay.toggled`

Each event includes: timestamp, route, user action metadata.

---

## 20. Progressive Delivery Plan (Incremental Milestones)

| Milestone | Scope |
|-----------|-------|
| M1 | Skeleton navigation + LiveScan placeholder + Settings stub |
| M2 | Integrate mock adapter → show fake detections overlay |
| M3 | Plate detail & history basic paging |
| M4 | Search + normalization + direct navigation |
| M5 | Real model adapter integration + performance overlay (dev) |
| M6 | Metadata editing + purge + config persistence |
| M7 | Polishing, accessibility pass, theming refinements |

---

## 21. Open Questions

| ID | Question | Notes |
|----|----------|-------|
| UI-Q1 | Adopt Riverpod vs Bloc? | Leaning Riverpod; finalize after prototype |
| UI-Q2 | Animated bounding boxes? | Possibly simple fade/scale for new detection |
| UI-Q3 | Dark mode support MVP? | Probably yes (Flutter theming) |
| UI-Q4 | Localized strings initial release? | EN only MVP, plan for intl later |
| UI-Q5 | Plate tagging taxonomy? | Free-form vs predefined sets |
| UI-Q6 | Confidence color thresholds? | Derive from domain config or UI constants? |
| UI-Q7 | Persist overlay layout preferences? | Possibly store dev toggles in meta_kv |

---

## 22. Future Enhancements

| Idea | Benefit |
|------|--------|
| Mini-map for clustered recognitions | Spatial insight |
| Timeline heatmap | Visual day/time frequency |
| Watchlist real-time banner | Immediate attention to flagged plates |
| Bulk tag edit in history | Faster curation |
| Offline export to encrypted bundle | Data portability |
| Onboarding tutorial overlay | Guided first-use experience |

---

## 23. Contribution Guidelines (UI)

| Aspect | Guideline |
|--------|-----------|
| File Organization | Group by feature under `lib/features/<feature_name>` |
| Widget Size | Keep files < ~300 lines; split complex widget trees |
| Naming | Avoid “Helper” / prefer descriptive nouns |
| State | Local ephemeral state with `StatefulWidget`; global reactive state in provider/riverpod scope |
| Testing | Golden tests for stable visuals; widget tests for interaction flows |
| Accessibility | Add semantic labels to icon-only buttons at creation |

---

## 24. Testing Matrix (UI Layer)

| Test Type | Target |
|-----------|--------|
| Widget Tests | Live scan overlay event render, history pagination |
| Golden Tests | Plate detail header variations (with/without notes) |
| Integration Tests | Search → open detail → back stack integrity |
| Performance Tests (dev) | Scroll history 1k items; ensure stable frame build times |
| Theming Tests | Dark mode snapshot diff |
| Accessibility Tests (manual + automation) | VoiceOver / TalkBack label verification |

---

## 25. Placeholder Wireframe Descriptions

(Visual assets to be added later; brief textual placeholders.)

1. LiveScanScreen:
   - Z-stack: Camera preview (full) + overlay layer + bottom horizontal recent strip.
2. PlateDetailScreen:
   - AppBar (back + title)
   - Header card (plate + stats)
   - Tabs or segmented control (Summary | Events)
   - Scrollable list below.
3. HistoryScreen:
   - Search bar (inline)
   - Virtual list items (plate, count, last seen)
   - Floating filter button (future).
4. SettingsScreen:
   - Section headers with dividers
   - Key-value rows + sliders + switches
   - Danger zone block at bottom.

---

## 26. Change Log

| Version | Summary |
|---------|---------|
| 0.1 | Initial UI features index scaffold |

---

End of document (v0.1)