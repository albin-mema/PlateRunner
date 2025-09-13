# Domain Model (Short)

Links: [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]] • [[../data/persistence|Persistence]] • [[../models/model_adapters|Model Adapters]] • [[../ui/features|UI Features]] • [[../dev/testing_strategy|Testing]] • [[../dev/performance|Performance]]
Backlinks: [[main|Index]] • [[../architecture/overview|Architecture]] • [[../architecture/pipeline|Pipeline]]

---

## Core Entities
| Entity | Purpose | Stored |
|--------|---------|--------|
| Plate | Canonical normalized plate + user metadata | Yes |
| RecognitionEvent | Single detection instance (ts, geo?, confidence) | Yes |
| PlateRecord | Aggregated view (computed + partial store) | Partial |
| ModelAdapter | Inference strategy (runtime abstraction) | Metadata optional |
| RecognitionCluster (future) | Windowed grouping to compress events | No (MVP) |

---

## Value Objects
PlateKey, GeoPoint (lat/long), ConfidenceScore (0..1), Frame (descriptor only), TimeWindow.

All immutable; equality = structural.

---

## Pure Services
- normalizePlate(raw, region?)
- fuseConfidence(rawScore, heuristicsCtx)
- dedupeEvents(existingWindow, newEvent)
- buildUpsertPlan(existingPlate?, event)
- aggregatePlateStats(events[])

Pure (no IO, no logging). Return data or Result type.

---

## Invariants
| ID | Rule |
|----|------|
| INV-PL-1 | normalized matches `[A-Z0-9\-]{2,16}` |
| INV-PL-2 | firstSeenTs ≤ lastSeenTs |
| INV-RE-1 | 0 ≤ confidence ≤ 1 |
| INV-RE-2 | geo present implies both lat & lon |
| INV-AGG-1 | totalRecognitions = COUNT(events) (periodic check) |

---

## Relationships
Plate 1—* RecognitionEvent (FK plateId).
PlateRecord = Plate + recent events + derived stats.

---

## Lifecycle
Plate: Nonexistent → Discovered (first event) → Enriched (user data) → (optional) Archived → Deleted (purge cascade).

---

## Error Model (Examples)
DM_INVALID_PLATE_FORMAT, DM_TIMESTAMP_SKEW, DM_CONFIDENCE_NAN, DM_UNSUPPORTED_REGION.
Represent as sealed/union results instead of throws (except programmer errors).

---

## Performance Notes
Normalization & fusion O(n) by plate length; dedupe window prunes rapid duplicates (default ~3s). Favor table-driven char ambiguity penalties.

---

## Extension Points
- Region format rules registry
- Confidence heuristic weights
- Dedup strategy parameters (time+geo future)
- Custom plate fields (json map)
- Event filtering threshold

---

## Open Decisions
| Topic | Options | Current Lean |
|-------|---------|--------------|
| Plate key | Natural vs UUID | UUID (merging flexibility) |
| Dedup dimensions | time vs time+geo | Start time-only |
| Confidence numeric | double vs fixed int | double |
| Region inference timing | inline vs background | inline (simple) |

---

## Minimal Pseudocode
```
raw = adapter.detect(frame)
norm = raw.map(normalizePlate).map(fuseConfidence).filter(conf>=cfg.min)
deduped = dedupeEvents(window, norm)
plans = deduped.map(p => buildUpsertPlan(load(p.key), p))
apply(plans) // side-effect layer
```

---

## Glossary
Normalized Plate: canonical uppercase form.  
Upsert Plan: pure structure describing DB mutations.  
Fused Confidence: adjusted score (raw - penalties).  
Dedup Window:temporal(and future geo) cluster boundary.

---

## Change Log
0.2 Short form replacement (Obsidian links)

