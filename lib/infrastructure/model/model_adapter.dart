/// Model Adapter Abstraction (Scaffold)
///
/// Provides a runtime‑agnostic contract for license plate recognition (LPR)
/// model implementations (TFLite, ONNX Runtime, native, mock, cloud fallback).
///
/// Goals:
/// - Decouple application + domain logic from any specific ML runtime.
/// - Support deterministic mocks for tests & replays.
/// - Enable future hot swap / degradation handling without leaking
///   backend specifics into higher layers.
/// - Keep this file pure Dart (no Flutter dependencies).
///
/// References:
/// - docs/models/model_adapters.md
/// - docs/architecture/pipeline.md
/// - docs/dev/performance.md
/// - docs/dev/testing_strategy.md
///
/// Conventions:
/// - All async APIs return Futures; no streams in MVP (polling or
///   controller pattern can be added later).
/// - No logging in this layer; surface metrics/errors via structured
///   results & error objects. Higher layers decide how to log.
/// - Avoid throwing for expected operational conditions (timeouts,
///   degradation); use typed result / error objects instead where feasible.
///
/// NOTE: This is a scaffold. Real adapters will live in sibling files
/// (e.g., `tflite_adapter.dart`, `onnx_adapter.dart`).
library model_adapter;
/// Web Compatibility Note:
/// For Flutter web builds (where native TFLite / ONNX runtimes are unavailable),
/// use `DeterministicMockAdapter` (already pure Dart) or provide a conditional
/// import with a lightweight web adapter (e.g. WASM, JS interop, or a stub).
/// Example future pattern:
///   import 'model_adapter_native.dart'
///       if (dart.library.html) 'model_adapter_web.dart';
/// Keep this core file platform-agnostic (no dart:html imports or platform
/// branching) so it remains usable across all targets.

import 'dart:math' as math;

/// Simple frame descriptor passed to adapter. Payload intentionally minimal for MVP.
/// Pixel buffers / platform handles are managed outside and only referenced
/// transiently during `detect()`.
class FrameDescriptor {
  final String id; // Correlation (monotonic string / UUID)
  final int epochMs;
  final int width;
  final int height;
  final FramePixelFormat format;

  const FrameDescriptor({
    required this.id,
    required this.epochMs,
    required this.width,
    required this.height,
    this.format = FramePixelFormat.yuv420,
  });
}

enum FramePixelFormat {
  /// YUV420 (common camera format)
  yuv420,

  /// 32-bit RGBA (rare direct feed)
  rgba8888,

  /// Other / opaque (adapter must convert or reject)
  unknown,
}

/// Options passed to a single inference call.
class InferenceOptions {
  /// Optional soft timeout override (ms).
  final int? inferenceTimeoutMs;

  /// Whether to request per-character scores (adapter may ignore).
  final bool requestCharScores;

  const InferenceOptions({
    this.inferenceTimeoutMs,
    this.requestCharScores = false,
  });
}

/// Model metadata describing static characteristics.
class ModelMetadata {
  final String id; // Stable symbolic id (e.g. tflite_v1_fast)
  final String version; // Semantic version or hash
  final ModelRuntime runtime;
  final ModelInputSpec inputSpec;
  final bool supportsBatch;
  final String? license;
  final int? warmupMsEstimate;

  const ModelMetadata({
    required this.id,
    required this.version,
    required this.runtime,
    required this.inputSpec,
    this.supportsBatch = false,
    this.license,
    this.warmupMsEstimate,
  });

  @override
  String toString() =>
      'ModelMetadata(id=$id, version=$version, runtime=$runtime, input=${inputSpec.width}x${inputSpec.height})';
}

enum ModelRuntime { tflite, onnx, native, mock, cloud }

/// Input tensor specification (single image).
class ModelInputSpec {
  final int width;
  final int height;
  final InputColorSpace colorSpace;
  const ModelInputSpec({
    required this.width,
    required this.height,
    this.colorSpace = InputColorSpace.rgb,
  });
}

enum InputColorSpace { rgb, yuv, gray }

/// Raw detection before domain normalization.
/// All fields immutable; adapter returns a new list per call.
class RawPlateDetection {
  final String rawText;
  final double confidenceRaw; // 0..1 (already sigmoid / calibrated)
  final BoundingBox bbox;
  final int inferenceTimeMs;
  final int qualityFlags; // bitmask (see QualityFlag)
  final List<double>? charScores; // Optional per-character scores
  final Map<String, Object?>? engineAux;

  const RawPlateDetection({
    required this.rawText,
    required this.confidenceRaw,
    required this.bbox,
    required this.inferenceTimeMs,
    required this.qualityFlags,
    this.charScores,
    this.engineAux,
  });

  RawPlateDetection copyWith({
    String? rawText,
    double? confidenceRaw,
    BoundingBox? bbox,
    int? inferenceTimeMs,
    int? qualityFlags,
    List<double>? charScores,
    Map<String, Object?>? engineAux,
  }) =>
      RawPlateDetection(
        rawText: rawText ?? this.rawText,
        confidenceRaw: confidenceRaw ?? this.confidenceRaw,
        bbox: bbox ?? this.bbox,
        inferenceTimeMs: inferenceTimeMs ?? this.inferenceTimeMs,
        qualityFlags: qualityFlags ?? this.qualityFlags,
        charScores: charScores ?? this.charScores,
        engineAux: engineAux ?? this.engineAux,
      );

  @override
  String toString() =>
      'RawPlateDetection(text="$rawText", conf=${confidenceRaw.toStringAsFixed(3)}, box=$bbox, t=${inferenceTimeMs}ms, flags=$qualityFlags)';
}

/// Rectangular bounding box with integer coordinates (pixel space).
class BoundingBox {
  final int left;
  final int top;
  final int width;
  final int height;
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  String toString() => '[$left,$top ${width}x$height]';
}

/// Bitmask quality flags (allow combination).
class QualityFlag {
  static const int blur = 1 << 0;
  static const int lowLight = 1 << 1;
  static const int partial = 1 << 2;
  static const int glare = 1 << 3;
  static const int occlusion = 1 << 4;

  static bool has(int mask, int flag) => (mask & flag) != 0;
}

/// Load modes controlling initialization cost / instrumentation.
enum ModelLoadMode { standard, fast, background, diagnostic }

/// Load status enumeration.
enum ModelLoadStatus { success, partial, failed }

/// Result of a load attempt.
class ModelLoadResult {
  final ModelLoadStatus status;
  final List<ModelLoadIssue> issues;
  final int initTimeMs;
  final bool warmupRan;

  const ModelLoadResult({
    required this.status,
    required this.issues,
    required this.initTimeMs,
    required this.warmupRan,
  });

  bool get isSuccess => status == ModelLoadStatus.success;

  @override
  String toString() =>
      'ModelLoadResult(status=$status, issues=${issues.length}, init=${initTimeMs}ms, warmup=$warmupRan)';
}

/// Detailed issue during load (non-fatal or fatal).
class ModelLoadIssue {
  final String code; // e.g. MODEL_FILE_MISSING
  final String message;
  final bool fatal;
  const ModelLoadIssue({
    required this.code,
    required this.message,
    this.fatal = false,
  });

  @override
  String toString() => '$code(fatal=$fatal): $message';
}

/// Health snapshot providing current high-level state & rolling metrics.
class ModelHealth {
  final ModelAdapterState state;
  final int? lastInferenceP95Ms;
  final int? memoryFootprintBytes;
  final double failureRatio; // window-based; 0..1
  final DateTime capturedAt;

  const ModelHealth({
    required this.state,
    required this.failureRatio,
    required this.capturedAt,
    this.lastInferenceP95Ms,
    this.memoryFootprintBytes,
  });
}

/// Adapter lifecycle states.
enum ModelAdapterState {
  uninitialized,
  loading,
  loaded,
  degraded,
  failed,
  disposed,
}

/// Base adapter error taxonomy.
sealed class ModelAdapterError implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
  const ModelAdapterError(this.message, {this.cause, this.stackTrace});

  @override
  String toString() =>
      '$runtimeType(message="$message"${cause != null ? ', cause=$cause' : ''})';
}

class ModelLoadError extends ModelAdapterError {
  const ModelLoadError(String message, {Object? cause, StackTrace? stackTrace})
      : super(message, cause: cause, stackTrace: stackTrace);
}

class ModelInferenceError extends ModelAdapterError {
  const ModelInferenceError(String message,
      {Object? cause, StackTrace? stackTrace})
      : super(message, cause: cause, stackTrace: stackTrace);
}

class ModelTimeoutError extends ModelAdapterError {
  final int timeoutMs;
  const ModelTimeoutError(this.timeoutMs,
      {String message = 'Inference timed out',
      Object? cause,
      StackTrace? stackTrace})
      : super('$message (timeoutMs=$timeoutMs)', cause: cause, stackTrace: stackTrace);
}

class AdapterDisposedError extends ModelAdapterError {
  const AdapterDisposedError()
      : super('Adapter already disposed; operation not permitted');
}

/// Abstract contract all model adapters must implement.
abstract class PlateModelAdapter {
  /// Return static metadata (available pre-load, but some fields may be
  /// finalized after successful initialization).
  ModelMetadata metadata();

  /// Load / initialize resources. Idempotent if already loaded.
  Future<ModelLoadResult> load({ModelLoadMode mode = ModelLoadMode.standard});

  /// Run inference for a single frame. MUST:
  /// - Throw [AdapterDisposedError] if disposed.
  /// - Throw [ModelInferenceError]/[ModelTimeoutError] for operational failures.
  /// - Never return null list; return empty on no detections.
  Future<List<RawPlateDetection>> detect(
    FrameDescriptor frame, {
    InferenceOptions? options,
  });

  /// Return quick health snapshot (cheap / non-blocking).
  Future<ModelHealth> health();

  /// Release all resources; idempotent.
  Future<void> dispose();
}

/// Deterministic mock adapter (MVP testing aid).
/// Generates pseudorandom but stable detections derived from frame.id.
/// NOT performance optimized; intended only for tests / development.
class DeterministicMockAdapter implements PlateModelAdapter {
  ModelAdapterState _state = ModelAdapterState.uninitialized;
  final ModelMetadata _meta;
  final int _simulatedLatencyMs;
  final int _maxPlatesPerFrame;
// ignore: unused_field
  final math.Random _rngSeeded;
  int _loadTimeMs = 0;

  DeterministicMockAdapter({
    String id = 'mock_deterministic_v1',
    String version = '1.0.0',
    int simulatedLatencyMs = 35,
    int maxPlatesPerFrame = 2,
    int seed = 42,
  })  : _meta = ModelMetadata(
          id: id,
            version: version,
            runtime: ModelRuntime.mock,
            inputSpec: const ModelInputSpec(width: 320, height: 192),
            supportsBatch: false,
          ),
          _simulatedLatencyMs = simulatedLatencyMs,
          _maxPlatesPerFrame = maxPlatesPerFrame,
          _rngSeeded = math.Random(seed);

  @override
  ModelMetadata metadata() => _meta;

  @override
  Future<ModelLoadResult> load({ModelLoadMode mode = ModelLoadMode.standard}) async {
    if (_state == ModelAdapterState.disposed) {
      return const ModelLoadResult(
        status: ModelLoadStatus.failed,
        issues: [ModelLoadIssue(code: 'ADAPTER_DISPOSED', message: 'Disposed', fatal: true)],
        initTimeMs: 0,
        warmupRan: false,
      );
    }
    if (_state == ModelAdapterState.loaded) {
      return ModelLoadResult(
        status: ModelLoadStatus.success,
        issues: const [],
        initTimeMs: _loadTimeMs,
        warmupRan: false,
      );
    }
    _state = ModelAdapterState.loading;
    final sw = Stopwatch()..start();
    // Simulated load / warmup cost
    await Future<void>.delayed(Duration(
        milliseconds: mode == ModelLoadMode.fast ? 10 : (_simulatedLatencyMs * 2)));
    sw.stop();
    _loadTimeMs = sw.elapsedMilliseconds;
    _state = ModelAdapterState.loaded;
    return ModelLoadResult(
      status: ModelLoadStatus.success,
      issues: const [],
      initTimeMs: _loadTimeMs,
      warmupRan: mode != ModelLoadMode.fast,
    );
  }

  @override
  Future<List<RawPlateDetection>> detect(FrameDescriptor frame,
      {InferenceOptions? options}) async {
    if (_state == ModelAdapterState.disposed) {
      throw const AdapterDisposedError();
    }
    if (_state == ModelAdapterState.uninitialized) {
      // Auto-load (optional behavior)
      await load();
    }
    if (_state != ModelAdapterState.loaded &&
        _state != ModelAdapterState.degraded) {
      throw ModelInferenceError(
          'Adapter state $_state does not allow detect()');
    }
    // Simulate latency
    await Future<void>.delayed(Duration(milliseconds: _simulatedLatencyMs));

    // Derive deterministic pseudo-random count
    final localRng = math.Random(_mix(frame.id.hashCode));
    final count = localRng.nextInt(_maxPlatesPerFrame + 1);

    final detections = <RawPlateDetection>[];
    for (var i = 0; i < count; i++) {
      final plate = _syntheticPlate(frame.id, i);
      final conf = 0.4 + (localRng.nextDouble() * 0.6); // 0.4 .. 1.0
      detections.add(
        RawPlateDetection(
          rawText: plate,
          confidenceRaw: double.parse(conf.toStringAsFixed(3)),
          bbox: BoundingBox(
            left: 10 + (i * 20),
            top: 20 + (i * 12),
            width: 100,
            height: 40,
          ),
            inferenceTimeMs: _simulatedLatencyMs,
            qualityFlags: _deriveQualityFlags(conf),
            charScores: null,
            engineAux: {
              'frameId': frame.id,
              'mockIndex': i,
            },
        ),
      );
    }
    return detections;
  }

  @override
  Future<ModelHealth> health() async => ModelHealth(
        state: _state,
        failureRatio: 0,
        capturedAt: DateTime.now(),
        lastInferenceP95Ms: _simulatedLatencyMs,
        memoryFootprintBytes: 256 * 1024, // mock estimate
      );

  @override
  Future<void> dispose() async {
    if (_state == ModelAdapterState.disposed) return;
    _state = ModelAdapterState.disposed;
  }

  // ---- Internal helpers ----

  int _mix(int h) {
    // Simple integer hash mixing for repeatability
    h = 0x1fffffff & (h + 0x9e3779b9);
    h = 0x1fffffff & (h ^ (h >> 16));
    h = 0x1fffffff & (h * 0x85ebca6b);
    h = 0x1fffffff & (h ^ (h >> 13));
    return h;
  }

  String _syntheticPlate(String frameId, int idx) {
    final base = frameId.hashCode ^ (idx * 7919);
    final letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final digits = '0123456789';
    final l1 = letters[base.abs() % letters.length];
    final l2 = letters[(base >> 5).abs() % letters.length];
    final d1 = digits[(base >> 9).abs() % digits.length];
    final d2 = digits[(base >> 13).abs() % digits.length];
    final d3 = digits[(base >> 17).abs() % digits.length];
    return '$l1$l2$d1$d2$d3';
  }

  int _deriveQualityFlags(double conf) {
    int mask = 0;
    if (conf < 0.55) mask |= QualityFlag.blur;
    if (conf < 0.50) mask |= QualityFlag.lowLight;
    if (conf > 0.90) mask |= QualityFlag.partial; // invert meaning for variety in mock
    return mask;
  }
}