# Feature TODO: Developer Overlay UI

Status: Draft (v0.1)  
Owner: (assign)  
Related: runtime_config_persistence.md • recognition_pipeline.md • ../architecture/pipeline.md • ../dev/performance.md
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]


---

## 1. Goal

Provide an in-app, lightweight, zero-network developer overlay to visualize live pipeline health and tunable diagnostics (FPS, inference latency, dedup effectiveness, recent plate recognitions, degradation state) without attaching an external profiler. Must be optionally enabled via `RuntimeConfig.enableDevOverlay` and impose negligible (<3–5 ms/frame) overhead when enabled.

---

## 2. Scope (MVP)

In-Scope:
- Floating overlay panel (draggable, collapsible) rendered above main UI.
- Live metrics: intake FPS, processed FPS, inference p50/p95, timeout count, dedupe ratio, pipeline state (NORMAL / DEGRADED), last recognition (plate + confidence).
- Lightweight ring buffer (N last recognitions) view (expandable section).
- Visual degradation indicator (color / badge).
- Manual config quick toggles (optional subset): sampling interval bump, active model id display (read-only), dev overlay hide.
- No persistent historical storage (ephemeral session only).
- No network export.

Out of Scope (MVP):
- Theming beyond dark translucent panel.
- Full charting (sparklines for later).
- Gesture-based performance recording.
- Advanced watchlist alerts.
- Multi-pane docking or multi-screen support.

---

## 3. Non-Goals

- Providing end-user (production) UX.
- Production analytics / telemetry shipping.
- Heavy animation or custom scene rendering.
- Security gating; overlay is dev-only (flag-based).

---

## 4. Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| OVERLAY-01 | Toggle visibility based on `RuntimeConfig.enableDevOverlay` stream | Must |
| OVERLAY-02 | Display real-time metrics snapshot updated ≤ 500ms cadence | Must |
| OVERLAY-03 | Show degradation state with color (e.g., amber/red) | Must |
| OVERLAY-04 | Show last recognition (plate + confidence%) | Must |
| OVERLAY-05 | Track & show count of skipped frames by reason | Should |
| OVERLAY-06 | Support collapse/expand to minimized pill | Must |
| OVERLAY-07 | Draggable reposition (persist session-only) | Should |
| OVERLAY-08 | No rebuild storms: diff & throttle updates | Must |
| OVERLAY-09 | Provide accessible semantic labels for test automation | Should |
| OVERLAY-10 | Self-disable automatically if performance cost detected (future) | Could |

---

## 5. Performance Constraints

| Aspect | Target |
|--------|--------|
| Overlay update interval | 250–500 ms (configurable) |
| Average added frame latency when enabled | < 3 ms |
| Memory overhead (buffers / retention) | < 500 KB |
| Rebuild frequency | ≤ 2 per second typical |

Strategies:
- Use `ValueListenable` or broadcast stream with throttled transformer.
- Precompute derived strings outside build.
- Avoid heavy ListView rebuilds; use `AnimatedSwitcher` minimal.

---

## 6. Data Inputs

Primary source: `PipelineMetricsSnapshot` (to be produced by metrics collector described in recognition_pipeline.md).  
Supplementary: `RuntimeConfig` stream snapshot.

Snapshot fields (planned):
```
PipelineMetricsSnapshot {
  int framesOffered;
  int framesProcessed;
  Map<String,int> framesSkippedByReason;
  int inferenceP50Ms;
  int inferenceP95Ms;
  int inferenceMaxMs;
  int timeouts;
  int errors;
  int rawDetections;
  int acceptedDetections;
  int persistedRecognitions;
  double dedupeRatio; // 1 - (accepted/raw) or accepted/raw normalized
  String state; // NORMAL | DEGRADED
  RecognitionPreview? lastRecognition; // { plate, confidence, tsMs }
  int lastUpdatedMs;
}
```

Overlay will not mutate upstream state—read-only consumption.

---

## 7. UI Layout (MVP Sketch)

Collapsed Pill:
```
[ DEV • NORMAL ] FPS 6.5 / 4.1 | p95 78ms | Last: ABC123 (0.87)
```

Expanded Panel:
```
+-----------------------------------------------------------+
| DEV OVERLAY (NORMAL)      [✕] [⇕ drag] [– collapse]       |
| Model: tflite_v1_fast  | Degraded: false                  |
| Frames: offered 245 | proc 158 | skip 87 (INTERVAL 60 ...)|
| Inference: p50 46ms p95 92ms max 140ms timeouts 2          |
| Dedupe: raw 210 → accepted 58 | ratio 72% filtered        |
| Last: ABC123 0.87 @12:44:03 (+info)                       |
| Recent (5): ABC123 0.87 | AB8123 0.66 | AB8123 0.72* ...  |
| Actions: [Increase Interval] [Reset Degrade] (future)     |
+-----------------------------------------------------------+
```

Visual Signals:
- Header background color:
  - Normal: neutral (indigo accent, 70% alpha).
  - Degraded: amber.
  - Error (future): red.

---

## 8. Interaction Model

| Interaction | Behavior |
|-------------|----------|
| Tap pill | Expand overlay |
| Drag header | Reposition within safe insets |
| Tap collapse | Return to pill |
| Tap close (if provided) | Set `enableDevOverlay=false` through config service |
| Resize (not MVP) | Deferred |

Dragged position persisted only in-memory (not runtime config) to avoid noise.

---

## 9. Configuration Integration

RuntimeConfig fields consumed:
- `enableDevOverlay` → visibility gate.
- Potential dynamic evaluation for:
  - `samplingIntervalMs` (display only)
  - `activeModelId`
  - `enableVerbosePipelineLogs` (maybe display badge)
  - `allowConcurrentDetect` (display concurrency mode)

Overlay should not frequently call `configService.update()` except for explicit user action (e.g., "Increase Interval" button). Provide helper to instrument such actions with logs `[OVERLAY] action=config_adjust key=samplingIntervalMs`.

---

## 10. Architecture / Implementation Plan

Layering:
```
metrics_collector (domain/infra) → overlay_controller (app/features) → overlay_widget (UI)
```

Components:
- `DevOverlayController`:
  - Subscribes to metrics + config streams.
  - Merges into `OverlayViewModel`.
  - Applies throttling (e.g., Rx `auditTime(300ms)` or manual timestamp gate).
- `OverlayViewModel` (immutable):
  - Preformatted strings (reduces rebuild work).
  - Diff equality by identity compare (recreate only when changed).
- `DevOverlayWidget`:
  - Stateful; tracks drag offset + collapsed state.
  - Accepts `OverlayViewModel`.
  - Uses `AnimatedPositioned` or `Stack` overlay insertion.
- Injection:
  - Insert via `Overlay` in `MaterialApp` builder or root `Stack` wrapper.

Approach Options:
1. Root `Stack` wrapping `Navigator` → Simpler, fewer overlay pitfalls.
2. Flutter `OverlayEntry` inserted after build → More flexible (choose for scalability).

MVP choose Option 1 for speed.

---

## 11. State Management Choice

Keep minimal: use a plain `StreamController<OverlayViewModel>` + throttled subscription in controller. Avoid introducing a full state management library here (until broader consistency decision—see open question about Riverpod in architecture doc).

---

## 12. Throttling & Rebuild Strategy

Algorithm:
1. Metrics stream emits high frequency (per processed frame) (potentially).
2. Controller receives → store latest snapshot.
3. If (now - lastEmit) >= 300 ms emit view model else schedule a delayed tick.
4. Config stream changes cause immediate re-emit (for toggles).

Edge: If degradation state flips, bypass throttle (force immediate).

---

## 13. Derived Computations

Inside controller (avoid widget doing math):
- FPS: `framesProcessed / windowSeconds` computed via sliding window or difference over last X seconds. MVP: maintain ring buffer of (timestampMs, framesProcessedTotal) pairs; compute delta over last 3000 ms.
- Dedupe filtering percent: `1 - (acceptedDetections / rawDetections)` with guard for divide-by-zero.
- Confidence display: format as `0.87` or percent `87%` (decide consistent style).
- Age of last recognition: (now - lastRecognition.tsMs) humanized if small (<10s).

---

## 14. Logging (Overlay Component)

Events (component `overlay`):
- `overlay_shown` { degraded: bool }
- `overlay_hidden`
- `overlay_collapsed`
- `overlay_expanded`
- `overlay_dragged` { x, y }
- `overlay_action` { action: "increase_interval" }
- `overlay_metrics_tick` (maybe sample one per N emits to avoid noise)

Minimize log noise when verbose logging disabled.

---

## 15. Accessibility & Testing Hooks

Keys / Semantics:
- `Key('dev_overlay_pill')`
- `Key('dev_overlay_panel')`
- `Key('dev_overlay_metric_inference_p95')`
- Provide `Semantics(label: 'Pipeline degraded')` when degraded.

Widget test strategy:
- Inject fake metrics controller that pushes deterministic snapshots.
- Verify text formatting & color changes on state change.

---

## 16. Error Handling

Failure sources are minimal (UI side). Potential errors:
- Null metrics snapshot (initial) → show placeholder "warming..."
- Exception in formatting (should not) → catch & show fallback line; log once.

---

## 17. Security / Privacy Considerations

- No raw frame data displayed.
- Plate strings displayed; this is acceptable in dev overlay. If future masking required, tie to config flag (`maskPlateText`).
- Overlay disabled in production builds by default (env check + runtime config default false).

---

## 18. Extensibility (Post-MVP)

Planned future features:
- Sparklines for latency & FPS (mini sparkline widget).
- Toggle detail view for a selected plate (link to history).
- Export last N metrics samples to clipboard.
- Performance budget warnings (color shift before degrade).
- Gesture double-tap to pin/unpin overlay for screenshot avoidance.
- Multi-section tabs (Metrics | Recognitions | Config).
- Real-time memory / battery usage integration (platform channel).
- Quick model hot-swap control (if multiple adapters registered).

---

## 19. Implementation Phases

Phase 1 (Core):
1. Define `OverlayViewModel`.
2. Implement `DevOverlayController` (throttle logic).
3. Add root wrapper injecting overlay widget when `enableDevOverlay=true`.
4. Add pill + panel UI with essential metrics + last recognition.

Phase 2 (Interaction):
5. Draggable reposition & collapsed state handling.
6. Add frame skip reasons breakdown (INTERVAL / QUEUE / etc.).
7. Add action button "Increase Interval" (mutates config via service.update()).

Phase 3 (Polish):
8. Improve formatting (adaptive width).
9. Add color-coded confidence (e.g., green >0.8, amber 0.6–0.8, red <0.6).
10. Add structured logs for overlay events.
11. Add widget & controller tests.

Phase 4 (Optional Enhancements):
12. Add small inference latency sparkline.
13. Add degrade auto-flash (brief highlight transition).

---

## 20. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| High update frequency causes jank | UI hitch | Throttle + diff check |
| Overlay covers critical UI elements | Usability reduced | Draggable + default corner position |
| Metrics collector changes contract | Break overlay | Strong typed snapshot + adapter layer |
| Drag persistence requested later | Feature creep | Keep ephemeral until validated |
| Confidence formatting confusion | Misinterpretation | Provide unified format (e.g., fixed 2 decimals) |

---

## 21. Open Questions

| ID | Question | Notes |
|----|----------|-------|
| OVERLAY-PQ-01 | Use OverlayEntry vs root Stack? | MVP chooses Stack |
| OVERLAY-PQ-02 | Provide hide-on-tap-outside? | Maybe; not MVP |
| OVERLAY-PQ-03 | Add haptic feedback on degrade? | Optional; low priority |
| OVERLAY-PQ-04 | Include DB txn p95 now or later? | Later when measured |
| OVERLAY-PQ-05 | Auto-disable after inactivity? | Consider for battery; not MVP |

---

## 22. Definition of Done (MVP)

- Toggling `enableDevOverlay` at runtime shows/hides overlay without restart.
- Real-time metrics update visible (FPS, inference p95, dedupe ratio, last recognition).
- Degraded state visibly signaled within ≤ 500 ms of state change.
- Performance overhead measured and within target (<3 ms additional cost).
- Widget & controller unit tests covering:
  - Throttling logic.
  - View model formatting.
  - Degraded color change.
- No uncaught exceptions during synthetic stress (5k metrics emits).
- Documentation (this file) updated with version bump.

---

## 23. View Model Draft

Fields (tentative):
```
class OverlayViewModel {
  final bool degraded;
  final String statusLine;        // "FPS 6.5 / 4.1 • p95 78ms"
  final String framesSummary;     // "offered 245 proc 158 skip 87"
  final String inferenceSummary;  // "p50 46 p95 92 max 140 timeout 2"
  final String dedupeSummary;     // "raw 210 → 58 kept (72% filtered)"
  final String lastRecognition;   // "ABC123 0.87"
  final List<String> recentPlates;// limited N
  final DateTime lastUpdate;
}
```

---

## 24. Testing Strategy (Detailed)

Controller Tests:
- Emits nothing until first metrics snapshot.
- Throttle: rapid sequence (10 snapshots < 100 ms) → ≤ 1 emit.
- Immediate emit on degraded transition boundary.
- Correct calculation of dedupe ratio with edge cases (raw==0).

Widget Tests:
- Renders pill then expanded panel on tap.
- Displays degraded color when viewModel.degraded = true.
- Drag gesture updates position (integration test optional).

Performance Test (manual dev harness):
- Inject synthetic metrics stream at 60 Hz.
- Confirm rebuild count approximate expected throttle (2–3 per second).

---

## 25. Task Checklist (Actionable)

- [ ] Create `DevOverlayController` & view model.
- [ ] Implement metrics throttling logic & diff equality.
- [ ] Insert overlay root wrapper behind a feature flag gate.
- [ ] Build pill + expanded panel UI.
- [ ] Wire runtime config subscription.
- [ ] Add last recognition ring buffer consumption.
- [ ] Implement draggable + collapsed state.
- [ ] Add action button (Increase Interval) -> config update.
- [ ] Add structured logging events.
- [ ] Create controller unit tests.
- [ ] Create widget tests (basic render & state transitions).
- [ ] Stress test performance with synthetic metrics.
- [ ] Update documentation & mark version 0.2 upon completion.

---

## 26. Future Metrics (Not MVP)

Potential additions:
- DB txn p95
- Memory usage (if inexpensive)
- Battery temperature or thermal state
- Queue depth sparkline
- Recognition confidence distribution mini-histogram

---

## 27. Change Log

| Version | Notes |
|---------|-------|
| 0.1 | Initial draft (scope, architecture, checklist) |

---

End of document (v0.1).