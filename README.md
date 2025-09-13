# PlateRunner

Offline‑first mobile License Plate Recognition prototype.  
Current focus: IMPLEMENT the live camera → model inference → normalization → (placeholder persistence) loop, replacing the temporary counter demo.

---

## 0. Why This Rewrite

Previously this README described a counter scaffold. We are pivoting to the actual LPR prototype. All near‑term work should advance a working camera + on‑device model pipeline, even if UI polish and full persistence come later.

---

## 1. Immediate Implementation Goals (Milestone: Live Scan Prototype)

| Order | Goal | Definition of Done |
|-------|------|--------------------|
| G1 | Camera preview | Renders continuous camera feed (rear camera) with correct aspect + lifecycle safe |
| G2 | Frame sampling | Periodically extracts frames (or YUV planes) at configurable interval |
| G3 | Model load | TFLite model assets (detection/OCR fused or mock) load successfully; metadata logged |
| G4 | Inference loop | Each sampled frame runs through adapter; raw plate strings + confidences returned |
| G5 | Domain normalization/fusion | `normalizePlate`, `fuseConfidence` applied; below-threshold filtered |
| G6 | Dedup window | Time-based suppression of rapid duplicates (~3s) in memory |
| G7 | Minimal overlay | Draw bounding boxes + plate text + confidence above threshold |
| G8 | Logging & metrics (dev) | Structured console lines `[PIPELINE] plate=... conf=... inferMs=...` |
| G9 | File import fallback | Pick an image from gallery / file system and run single inference |
| G10 | Tech debt sweep | Remove unused counter UI; document adapter + camera integration notes |

Stretch (not blocking prototype):
- Basic in-memory persistence of accepted events
- Settings panel for min confidence & sampling interval
- Simple performance stats overlay (FPS, inference ms)

---

## 2. Current Tech Stack (Prototype)

| Concern | Package |
|---------|---------|
| Camera feed | `camera` |
| Gallery / file pick | `image_picker` |
| On-device model runtime | `tflite_flutter` (+ `tflite_flutter_helper` if needed) |
| Permissions | `permission_handler` |
| Model abstraction | `PlateModelAdapter` (custom scaffold) |
| Domain core | Pure Dart in `lib/domain` |

---

## 3. Model Assets

Place models under:
```
assets/models/
  detector.tflite          # (example) combined plate detect + OCR
  labels.txt               # (optional) class/charset labels
```

Update `pubspec.yaml` assets list already configured.

Model requirements (initial):
- Accept single image tensor (e.g., 320x192 RGB/YUV converted)
- Emit candidate plate strings with a confidence score
- Latency aim: <120ms p95 mid device (not enforced yet)

If no real model yet, continue using `DeterministicMockAdapter` until integrated.

---

## 4. Camera + Frame Sampling Plan

1. Initialize `CameraController` (rear camera, medium resolution balancing inference cost).
2. Start stream via `controller.startImageStream(onFrame)`.
3. Sampling: throttle frames (e.g., every Nth or every X ms) based on runtime config.
4. Convert `CameraImage` YUV → RGB (if model requires) with minimal copies (prefer direct plane conversion).
5. Wrap into `FrameDescriptor` → pass to active adapter.

Backpressure: If an inference is inflight, skip new frame until it returns (serialized MVP).

---

## 5. Inference Loop (Pseudocode)

```
onSampledFrame(frame):
  if (adapterBusy) return
  adapterBusy = true
  final detections = await adapter.detect(frame)
  final now = clockMs()
  final accepted = <DetectionResult>[]
  for d in detections:
     normRes = normalizePlate(d.rawText)
     if failure -> continue
     fused = fuseConfidence(contextFromQualityFlags(d.qualityFlags, d.confidenceRaw))
     if fused.value < cfg.minFusedConfidence -> continue
     if dedupeCache.isDuplicate(normPlate, now) -> continue
     dedupeCache.remember(normPlate, now)
     accepted.add(...)
  overlay.update(accepted, frameMetadata)
  log "[PIPELINE] ..."
  adapterBusy = false
```

---

## 6. Minimal Overlay Requirements

- Bounding box rectangle
- Plate text (normalized) + fused confidence (e.g. 0.87)
- Color cue by confidence (simple thresholds: <0.65 amber, ≥0.65 green)
- Most recent N plates (horizontal chip row at bottom or transient fade)

Defer advanced UI (history, search) until pipeline works reliably.

---

## 7. File / Image Import Flow

Purpose: local testing without live camera or to run static sample images.

Steps:
1. User taps “Import Image” (temporary button/fab).
2. `image_picker` returns file path.
3. Load bytes → convert to required tensor shape.
4. Run `adapter.detect()` once; push results through same normalization + overlay pipeline.

Add several sample images under `assets/samples/` for deterministic manual testing.

---

## 8. Runtime Config (Relevant Fields Right Now)

| Field | Description | Default |
|-------|-------------|---------|
| `minFusedConfidence` | Post-fusion acceptance threshold | 0.55 |
| `dedupeWindowMs` | Time suppression window | 3000 |
| `samplingIntervalMs` | Target ms between frame samples | 150 |
| `activeModelId` | Selected adapter id | `tflite_v1_fast` (or mock) |

Expose quick adjustments via a temporary debug drawer or dev overlay (OK to be crude).

---

## 9. Transition Plan from Counter Demo

| Step | Action |
|------|--------|
| 1 | Remove counter UI from `main.dart`, introduce `LiveScanPage` |
| 2 | Add camera permission request & error handling |
| 3 | Implement sampling + mock adapter integration first |
| 4 | Swap mock adapter with real TFLite adapter (load model asset) |
| 5 | Add overlay rendering layer |
| 6 | Add file import button |
| 7 | Add logs + simple performance counters |
| 8 | Delete obsolete counter tests; add live scan smoke test (adapter mocked) |

---

## 10. Error / Permission Handling (MVP)

| Case | UX |
|------|----|
| Camera permission denied (permanent) | Center message + “Open Settings” button |
| Camera initialization failure | Snackbar + retry button |
| Model load failure | Message with “Retry” / fallback to mock |
| No detections after N frames | (Dev only) log advisory |

---

## 11. Logging Examples

```
[PIPELINE] frame=123 ts=... detectMs=42 plates=2 accepted=1 dedup=1
[MODEL] id=tflite_v1_fast loadMs=612 warmup=true
[MODEL] inference frame=124 latencyMs=38 detections=2
```

Keep logs concise; reduce verbosity outside dev builds.

---

## 12. Testing Focus Shift

Short term automated tests:
- Adapter load/detect smoke (mock + (when present) real model behind flag)
- Normalization / fusion already covered
- Dedupe window logic property tests
- Live scan widget: camera stream stub -> ensures overlay updates

Defer heavy scenario / persistence tests until core loop stable.

---

## 13. Open Implementation Questions

| Topic | Question | Tentative Answer |
|-------|----------|------------------|
| Model separation (detect vs OCR) | Use unified model or two-stage? | Start unified if available |
| Frame scaling | Pre-scale in Dart vs delegate in native? | Measure; start simple |
| YUV → RGB conversion | Custom vs helper lib | Use existing helper; optimize later |
| Adapter concurrency | Single in-flight vs queue | Single (deterministic, simpler) |
| Bounding box coordinate space | Raw model vs scaled preview | Map once; maintain aspect ratio letterboxing awareness |

---

## 14. Running the Prototype

1. Ensure model file(s) placed in `assets/models/` and entry added in `pubspec.yaml`.
2. `flutter pub get`
3. (Android) `flutter run -d <device>` (cold start prompts camera permission)
4. Observe DEV logs for model load + inference lines.
5. Use temporary UI buttons:
   - “Toggle Adapter” (mock ↔ real) (optional)
   - “Import Image”

If no real model yet: comment real adapter instantiation; only mock runs.

---

## 15. Troubleshooting (Prototype-Specific)

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| Black preview | Camera not initialized / permission denied | Check permission flow & controller init |
| High latency spikes | Debug build + slow device | Try release/profile build, reduce resolution |
| No detections | Model mismatch / threshold too high | Lower `minFusedConfidence`, verify model path |
| App crash on Android start | Missing camera permission in manifest | Add `<uses-permission android:name="android.permission.CAMERA" />` |
| iOS build fails for tflite | Pod install / architecture mismatch | `cd ios && pod repo update && pod install` |

---

## 16. Near-Term Backlog (Post G1–G10)

- SQLite persistence layer & upsert application
- History screen & detail view
- Config/settings UI
- Performance metrics overlay
- Geo capture & extended dedupe (time+geo optional)
- Plate metadata editing
- Data purge action

---

## 17. License

Currently unlicensed (private/internal). Add proper license before distribution.

---

## 18. Reference & Documentation Index

Central index (keep in sync when adding docs). Also see `main.md` and Obsidian-style wiki links inside sub‑docs.

### Core Architecture
- `docs/architecture/overview.md`
- `docs/architecture/pipeline.md`
- `docs/architecture/adrs/ADR-000-template.md` (ADR Template)

### Domain & Data
- `docs/data/domain_model.md`
- `docs/data/persistence.md`

### Models
- `docs/models/model_adapters.md`

### Pipeline & Feature Specs (TODOs)
- `docs/features/todo/recognition_pipeline.md`
- `docs/features/todo/runtime_config_persistence.md`
- `docs/features/todo/dev_overlay_ui.md`
- `docs/features/todo/plate_history_feature.md`
- `docs/features/todo/README.md` (feature spec index)

### UI / UX
- `docs/ui/features.md`

### Development Process
- `docs/dev/testing_strategy.md`
- `docs/dev/performance.md`
- `codestyle.md`

### Governance & AI
- `agents.md` (AI Agents Guide)

### Cross-Link Guidance
- When adding a new doc, add a bullet in the appropriate category above.
- Add relative links between related docs (e.g., pipeline ↔ model adapters, persistence ↔ domain model).
- Update `main.md` if a new document is broadly useful (architecture, domain, performance).
- Keep category ordering stable; append new bullets to reduce merge conflicts.
- Prefer short “short form” docs that deep-link to more detailed ADRs or specs rather than bloating this README.


---

Focused forward: implement the live pipeline first—refine later.