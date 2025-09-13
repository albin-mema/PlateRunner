/// Recognition Pipeline Orchestrator (Initial Scaffold)
///
/// Purpose:
///   Bridge imperative shell (camera frames + model adapter) with pure
///   domain logic (normalization, confidence fusion, dedupe, upsert planning).
///
/// Scope (MVP):
///   - Frame intake with simple fixed-interval sampling
///   - Single in-flight model inference (serialized)
///   - Raw → normalized + fused → dedupe (time window)
///   - Emit accepted (post-dedupe) `RecognitionEvent`s to listeners
///   - Provide basic lifecycle: start / stop / dispose
///
/// Non-Goals (for this initial scaffold):
///   - Actual persistence (UpsertPlan produced but not applied)
///   - Advanced sampling (motion / adaptive heuristics)
///   - Degradation state machine
///   - Metrics histograms & percentiles
///   - Structured logging implementation (only callback hooks)
///   - Geo distance dedupe
///
/// Integration Points:
///   - Camera layer calls `feedFrame(frameDescriptor)` opportunistically.
///   - Higher layer subscribes to `events` stream to update UI / caches.
///   - Future persistence layer will subscribe to `plans` stream.
///
/// Threading / Concurrency (Simplified):
///   - Assumes single isolate usage for now.
///   - At most one inference active; latest pending frame retained if new
///     frames arrive while busy (older pending replaced).
///
/// Key Configuration Inputs (from `RuntimeConfig`):
///   - samplingIntervalMs (min interval between processed frames)
///   - minFusedConfidence (filter threshold)
///   - dedupeWindowMs (temporal dedupe window)
///   - allowConcurrentDetect (currently ignored; always false in MVP)
///
/// Extension Seams:
///   - Replace `_shouldSampleFrame` with strategy interface later.
///   - Swap model adapter (TFLite / Mock) without changing orchestrator.
///   - Insert persistence consumer of `_planController`.
///
/// References:
///   - docs/architecture/pipeline.md
///   - docs/models/model_adapters.md
///   - docs/data/domain_model.md
///
/// NOTE:
///   This file intentionally contains pragmatic placeholder logic to get the
///   end-to-end loop running. Refactor after baseline functionality + tests.
///
/// Author: Initial scaffold by AI assistant (iterate freely).
library recognition_pipeline;

import 'dart:async';

import 'package:plate_runner/domain/plate_entities.dart';
import 'package:plate_runner/infrastructure/model/model_adapter.dart';
import 'package:plate_runner/shared/config/runtime_config.dart';

/// Time provider (injectable for deterministic tests).
typedef NowEpochMs = int Function();

/// PlateId generator (external so tests can control determinism).
typedef PlateIdGenerator = PlateId Function();

/// Logging callback (structured) – use lightweight map so caller can encode.
/// Avoid allocating heavy objects in hot path unless dev mode.
typedef PipelineLogSink = void Function(Map<String, Object?> event);

/// Public pipeline lifecycle states.
enum PipelineState {
  idle,
  starting,
  running,
  stopping,
  stopped,
  disposed,
  error,
}

/// Output wrapper for subscribers (post-dedupe recognition event).
class PipelineRecognition {
  final RecognitionEvent event;
  final RawPlateDetection raw; // raw detection that produced event
  final ConfidenceFusionContext fusionCtx;
  final double fusedConfidence;
  final Duration inferenceLatency;
  final String modelId;

  const PipelineRecognition({
    required this.event,
    required this.raw,
    required this.fusionCtx,
    required this.fusedConfidence,
    required this.inferenceLatency,
    required this.modelId,
  });
}

/// Upsert plan envelope (placeholder until persistence wired).
class PipelineUpsert {
  final UpsertPlan plan;
  final PipelineRecognition source;
  const PipelineUpsert({
    required this.plan,
    required this.source,
  });
}

/// Aggregated, lightweight pipeline statistics snapshot.
/// NOTE: Counts are monotonic since pipeline start (reset on restart).
class PipelineStats {
  final int framesOffered;
  final int framesSampleAccepted;
  final int inferenceCount;
  final int rawDetections;
  final int recognitionsEmitted;
  final int inferenceLatencyAvgMs;
  final int inferenceLatencyMaxMs;

  const PipelineStats({
    required this.framesOffered,
    required this.framesSampleAccepted,
    required this.inferenceCount,
    required this.rawDetections,
    required this.recognitionsEmitted,
    required this.inferenceLatencyAvgMs,
    required this.inferenceLatencyMaxMs,
  });

  @override
  String toString() =>
      'PipelineStats(framesOffered=$framesOffered, accepted=$framesSampleAccepted, '
      'inferenceCount=$inferenceCount, rawDetections=$rawDetections, emitted=$recognitionsEmitted, '
      'latAvgMs=$inferenceLatencyAvgMs, latMaxMs=$inferenceLatencyMaxMs)';
}

/// Recognition Pipeline Orchestrator.
class RecognitionPipeline {
  final PlateModelAdapter _adapter;
  final RuntimeConfigService _configService;
  final NowEpochMs _now;
  final PlateIdGenerator _plateIdGen;
  final PipelineLogSink? _log;

  PipelineState _state = PipelineState.idle;

  // Frame sampling
  int _lastProcessedFrameMs = 0;
  FrameDescriptor? _pendingFrame;
  bool _inferenceActive = false;

  // Dedupe window buffer (post-normalization events).
  final List<RecognitionEvent> _recentEventsWindow = [];

  // Controllers
  final StreamController<PipelineRecognition> _eventController =
      StreamController.broadcast();
  final StreamController<PipelineUpsert> _planController =
      StreamController.broadcast();
  final StreamController<PipelineState> _stateController =
      StreamController.broadcast();
  // New stats controller (broadcast).
  final StreamController<PipelineStats> _statsController =
      StreamController.broadcast();

  // ---- Metrics Counters (monotonic) ----
  int _framesOffered = 0;
  int _framesSampleAccepted = 0;
  int _inferenceCount = 0;
  int _rawDetections = 0;
  int _recognitionsEmitted = 0;
  int _inferenceLatencyAccumMs = 0;
  int _inferenceLatencyMaxMs = 0;

  void _recordFrameOffered() {
    _framesOffered++;
  }

  void _recordFrameAcceptedForSampling() {
    _framesSampleAccepted++;
  }

  void _recordInference(int latencyMs, int detections) {
    _inferenceCount++;
    _rawDetections += detections;
    _inferenceLatencyAccumMs += latencyMs;
    if (latencyMs > _inferenceLatencyMaxMs) {
      _inferenceLatencyMaxMs = latencyMs;
    }
  }

  void _recordRecognitions(int count) {
    _recognitionsEmitted += count;
  }

  void _emitStats() {
    if (_statsController.isClosed) return;
    final avg = _inferenceCount == 0
        ? 0
        : (_inferenceLatencyAccumMs / _inferenceCount).round();
    _statsController.add(
      PipelineStats(
        framesOffered: _framesOffered,
        framesSampleAccepted: _framesSampleAccepted,
        inferenceCount: _inferenceCount,
        rawDetections: _rawDetections,
        recognitionsEmitted: _recognitionsEmitted,
        inferenceLatencyAvgMs: avg,
        inferenceLatencyMaxMs: _inferenceLatencyMaxMs,
      ),
    );
  }

  bool _disposed = false;

  RecognitionPipeline({
    required PlateModelAdapter adapter,
    required RuntimeConfigService configService,
    PlateIdGenerator? plateIdGen,
    NowEpochMs? now,
    PipelineLogSink? logSink,
  })  : _adapter = adapter,
        _configService = configService,
        _plateIdGen = plateIdGen ?? _defaultPlateIdGen,
        _now = now ?? _defaultNow,
        _log = logSink {
    // React to runtime config updates if needed (e.g., dynamic thresholds).
    _configService.updates.listen((_) {
      // Currently just emitted; could trigger internal reconfig actions later.
      _emitLog('config_update', {
        'minFusedConfidence': _configService.current.minFusedConfidence,
        'dedupeWindowMs': _configService.current.dedupeWindowMs,
      });
    });
  }

  // ---- Public Streams ----

  Stream<PipelineRecognition> get events => _eventController.stream;
  Stream<PipelineUpsert> get plans => _planController.stream;
  Stream<PipelineState> get states => _stateController.stream;
  Stream<PipelineStats> get stats => _statsController.stream;

  PipelineState get state => _state;

  // ---- Lifecycle ----

  Future<void> start() async {
    if (_disposed) {
      throw StateError('Pipeline disposed');
    }
    if (_state == PipelineState.running ||
        _state == PipelineState.starting) {
      return;
    }
    _transition(PipelineState.starting);
    _emitLog('pipeline_start', {'adapter': _adapter.metadata().id});

    // Ensure adapter loaded
    final loadResult = await _adapter.load();
    if (!loadResult.isSuccess) {
      _emitLog('adapter_load_failed', {
        'issues': loadResult.issues.map((i) => i.code).toList(),
      });
      _transition(PipelineState.error);
      return;
    }

    _emitLog('adapter_loaded', {
      'initTimeMs': loadResult.initTimeMs,
      'warmupRan': loadResult.warmupRan,
    });

    _transition(PipelineState.running);
  }

  Future<void> stop() async {
    if (_disposed) return;
    if (_state != PipelineState.running) return;
    _transition(PipelineState.stopping);
    _emitLog('pipeline_stop', {});
    // No long-running workers yet; just flag state.
    _transition(PipelineState.stopped);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _transition(PipelineState.disposed);
    await _adapter.dispose();
    await _eventController.close();
    await _planController.close();
    await _stateController.close();
    await _statsController.close();
    _disposed = true;
  }

  // ---- Frame Intake ----

  /// Offer a frame to the pipeline. The pipeline decides whether to sample it.
  void feedFrame(FrameDescriptor frame) {
    if (_state != PipelineState.running) return;
    _recordFrameOffered();
    final cfg = _configService.current;
    final nowMs = _now();
    if (!_shouldSampleFrame(
        nowMs, _lastProcessedFrameMs, cfg.samplingIntervalMs)) {
      _emitLog('frame_skipped', {
        'reason': 'INTERVAL',
        'frameTs': frame.epochMs,
        'sinceLast': nowMs - _lastProcessedFrameMs,
      });
      _emitStats();
      return;
    }
    _recordFrameAcceptedForSampling();
    // Accept frame
    _pendingFrame = frame;
    _lastProcessedFrameMs = nowMs;
    _drain(); // attempt to schedule inference
    _emitStats();
  }

  /// Bypass sampling interval for imported / batch frames.
  ///
  /// Use for offline media (e.g., video/image imports) where every provided
  /// frame (or pre-sampled subset) should be processed irrespective of the
  /// realtime sampling throttle applied to live camera feed.
  ///
  /// Still updates metrics counters & emits a log event so batch sessions can
  /// be analyzed. Intentionally mirrors the acceptance path of [feedFrame]
  /// without the interval gate.
  void ingestImportedFrame(FrameDescriptor frame) {
    if (_state != PipelineState.running) return;
    _recordFrameOffered();
    _recordFrameAcceptedForSampling();
    _pendingFrame = frame;
    // Advance last processed timestamp to avoid a burst of subsequent live
    // frames immediately passing the interval gate unintentionally.
    _lastProcessedFrameMs = _now();
    _emitLog('import_frame_ingested', {
      'frameId': frame.id,
      'w': frame.width,
      'h': frame.height,
    });
    _drain();
    _emitStats();
  }

  // ---- Internal Scheduling / Processing ----

  void _drain() {
    if (_inferenceActive) {
      // We'll pick up the latest pending frame when current finishes.
      return;
    }
    if (_pendingFrame == null) return;
    final frame = _pendingFrame!;
    _pendingFrame = null;
    _runInference(frame);
  }

  Future<void> _runInference(FrameDescriptor frame) async {
    _inferenceActive = true;
    final adapterId = _adapter.metadata().id;
    final started = _now();
    List<RawPlateDetection> raws = const [];
    try {
      raws = await _adapter.detect(frame);
    } on ModelAdapterError catch (e, st) {
      _emitLog('inference_error', {
        'error': e.runtimeType.toString(),
        'message': e.message,
        'stack': st.toString(),
      });
      _inferenceActive = false;
      _drain(); // attempt next if pending
      return;
    } catch (e, st) {
      _emitLog('inference_unknown_error', {
        'error': e.toString(),
        'stack': st.toString(),
      });
      _inferenceActive = false;
      _drain();
      return;
    }
    final latencyMs = _now() - started;
    _emitLog('inference_complete', {
      'detections': raws.length,
      'latencyMs': latencyMs,
      'model': adapterId,
    });
    _recordInference(latencyMs, raws.length);
    _emitStats();

    if (raws.isEmpty) {
      _inferenceActive = false;
      _drain();
      return;
    }

    _processDetections(
      frame: frame,
      raws: raws,
      inferenceLatencyMs: latencyMs,
      modelId: adapterId,
    );

    _inferenceActive = false;
    // Process next pending frame (if any)
    _drain();
  }

  void _processDetections({
    required FrameDescriptor frame,
    required List<RawPlateDetection> raws,
    required int inferenceLatencyMs,
    required String modelId,
  }) {
    final cfg = _configService.current;
    final nowMs = _now();

    final acceptedEvents = <RecognitionEvent>[];
    final recognitions = <PipelineRecognition>[];

    for (final raw in raws) {
      // 1. Normalize text
      final normResult = normalizePlate(raw.rawText);
      if (normResult is Failure<NormalizedPlate, DomainError>) {
        _emitLog('normalize_reject', {
          'raw': raw.rawText,
          'reason': normResult.error.toString(),
        });
        continue;
      }
      final normalized = (normResult as Success<NormalizedPlate, DomainError>).value;

      // 2. Build fusion context
      final fusionCtx = _fusionContextFromRaw(raw);

      // 3. Fuse confidence
      final fusedResult = fuseConfidence(fusionCtx);
      if (fusedResult is Failure<ConfidenceScore, DomainError>) {
        _emitLog('confidence_fusion_error', {
          'rawScore': raw.confidenceRaw,
          'error': fusedResult.error.toString(),
        });
        continue;
      }
      final fusedScore = (fusedResult as Success<ConfidenceScore, DomainError>).value;

      if (fusedScore.value < cfg.minFusedConfidence) {
        _emitLog('confidence_below_threshold', {
          'plate': normalized.value,
          'fused': fusedScore.value,
          'threshold': cfg.minFusedConfidence,
        });
        continue;
      }

      // 4. Build temporary recognition event (plateId placeholder)
      final tempPlateId = _plateIdGen(); // will be replaced if existing later
      final event = RecognitionEvent(
        plateId: tempPlateId,
        plate: normalized,
        confidence: fusedScore,
        timestamp: nowMs,
      );

      acceptedEvents.add(event);

      recognitions.add(
        PipelineRecognition(
          event: event,
          raw: raw,
          fusionCtx: fusionCtx,
            fusedConfidence: fusedScore.value,
            inferenceLatency: Duration(milliseconds: inferenceLatencyMs),
            modelId: modelId,
        ),
      );
    }

    if (acceptedEvents.isEmpty) {
      return;
    }

    // 5. Dedupe (time window)
    final deduped = dedupeEvents(
      existing: _recentEventsWindow,
      incoming: acceptedEvents,
      window: Duration(milliseconds: cfg.dedupeWindowMs),
    );

    final addedCount = deduped.length - _recentEventsWindow.length;
    if (addedCount <= 0) {
      _emitLog('dedupe_suppressed_all', {
        'incoming': acceptedEvents.length,
        'existingWindow': _recentEventsWindow.length,
      });
      return;
    }

    // Determine which events are new (tail diff)
    final newEvents =
        deduped.sublist(deduped.length - addedCount, deduped.length);

    // Update window buffer
    _recentEventsWindow
      ..clear()
      ..addAll(_pruneWindow(
        events: deduped,
        nowMs: nowMs,
        windowMs: cfg.dedupeWindowMs,
      ));

    // 6. Emit pipeline recognitions (only for new events)
    int emittedThisBatch = 0;
    for (final rec in recognitions) {
      final isNew = newEvents.any((e) => identical(e, rec.event) || _sameEvent(e, rec.event));
      if (!isNew) {
        _emitLog('dedupe_suppressed_single', {
          'plate': rec.event.plate.value,
          'confidence': rec.event.confidence.value,
        });
        continue;
      }

      _eventController.add(rec);
      emittedThisBatch++;

      // 7. Build UpsertPlan (placeholder, no actual repository yet)
      final plan = buildUpsertPlan(
        existing: null, // repository lookup would go here
        event: rec.event,
        newPlateIdProvider: _plateIdGen,
      );
      _planController.add(PipelineUpsert(plan: plan, source: rec));

      _emitLog('recognition_emit', {
        'plate': rec.event.plate.value,
        'confidence': rec.event.confidence.value,
        'model': modelId,
      });
    }

    if (emittedThisBatch > 0) {
      _recordRecognitions(emittedThisBatch);
      _emitStats();
    }
  }

  // ---- Helpers ----

  void _transition(PipelineState next) {
    if (_state == next) return;
    _state = next;
    _stateController.add(next);
  }

  bool _shouldSampleFrame(int nowMs, int lastMs, int intervalMs) {
    final delta = nowMs - lastMs;
    return delta >= intervalMs;
  }

  ConfidenceFusionContext _fusionContextFromRaw(RawPlateDetection raw) {
    final flags = raw.qualityFlags;
    return ConfidenceFusionContext(
      rawScore: raw.confidenceRaw,
      lowLight: QualityFlag.has(flags, QualityFlag.lowLight),
      partial: QualityFlag.has(flags, QualityFlag.partial),
      blurred: QualityFlag.has(flags, QualityFlag.blur),
    );
  }

  List<RecognitionEvent> _pruneWindow({
    required List<RecognitionEvent> events,
    required int nowMs,
    required int windowMs,
  }) {
    final cutoff = nowMs - windowMs;
    return events.where((e) => e.timestamp >= cutoff).toList(growable: true);
  }

  bool _sameEvent(RecognitionEvent a, RecognitionEvent b) =>
      a.plate == b.plate && a.timestamp == b.timestamp;

  void _emitLog(String event, Map<String, Object?> data) {
    _log?.call({
      'ts': _now(),
      'component': 'pipeline',
      'event': event,
      ...data,
    });
  }
}

// ---- Default Providers ----

int _defaultNow() => DateTime.now().millisecondsSinceEpoch;

PlateId _defaultPlateIdGen() =>
    PlateId.fromString('tmp_${DateTime.now().microsecondsSinceEpoch}');

// ---- Example Usage (Documentation Only) ----
//
// final pipeline = RecognitionPipeline(
//   adapter: DeterministicMockAdapter(),
//   configService: InMemoryRuntimeConfigService.withDefaults(),
//   logSink: (e) => print('[PIPELINE] $e'),
// );
//
// await pipeline.start();
// cameraFrames.listen(pipeline.feedFrame);
// pipeline.events.listen((rec) {
//   debugPrint('Plate: ${rec.event.plate} conf=${rec.fusedConfidence}');
// });
//
// On dispose:
// await pipeline.dispose();
//
// (End example)