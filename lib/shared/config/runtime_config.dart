/// Runtime Configuration Service (Scaffold)
///
/// Provides a lightweight, immutable snapshot-based configuration system
/// for tunable runtime parameters (confidence thresholds, dedupe window,
/// sampling, model selection, feature flags, dev toggles, etc.).
///
/// Design Goals:
/// - Pure immutable snapshot object (`RuntimeConfig`) passed into logic.
/// - Centralized defaults (no scattering magic numbers).
/// - Support dynamic updates (in-memory) for dev / settings UI.
/// - Easily persistable via a key/value adapter (future).
/// - Avoid tight coupling to Flutter; pure Dart only.
///
/// Non-Goals (MVP):
/// - Persistent storage layer (delegated to future adapter).
/// - Remote feature flagging.
/// - Multi-tenant / environment layering beyond defaults + overrides.
///
/// References:
/// - docs/dev/performance.md
/// - docs/architecture/overview.md
/// - docs/models/model_adapters.md
///
/// Usage Pattern:
///   final svc = InMemoryRuntimeConfigService.withDefaults();
///   final cfg = svc.current;
///   pipeline.configure(cfg);
///   svc.updates.listen((c) => pipeline.reconfigure(c));
///
/// Adding a new config field:
/// 1. Add to `RuntimeConfig`.
/// 2. Add default in `_defaultConfig()`.
/// 3. Optionally expose typed getter in service extension.
///
library runtime_config;

import 'dart:async';

// ---------------------------------------------------------------------------
// Immutable Config Snapshot
// ---------------------------------------------------------------------------

/// Immutable value object containing *all* tunable fields.
/// Keep constructor private; use [RuntimeConfig.build] / copyWith.
final class RuntimeConfig {
  final double minFusedConfidence;
  final int dedupeWindowMs;
  final String activeModelId;
  final bool enableDevOverlay;
  final bool enableCharScores;
  final int modelInferenceTimeoutMs;
  final int degradeP95LatencyMs;
  final int degradeFailureWindow;
  final bool allowConcurrentDetect;
  final int samplingIntervalMs;
  final bool enableStructuredLogs;
  final bool enableVerbosePipelineLogs;
  final int recentPlatesLimit;
  final int maxRecentEventsWindowPerPlate;
  final int purgeRetentionDays; // future: used by scheduled retention
  final Map<String, Object?> featureFlags;

  const RuntimeConfig._({
    required this.minFusedConfidence,
    required this.dedupeWindowMs,
    required this.activeModelId,
    required this.enableDevOverlay,
    required this.enableCharScores,
    required this.modelInferenceTimeoutMs,
    required this.degradeP95LatencyMs,
    required this.degradeFailureWindow,
    required this.allowConcurrentDetect,
    required this.samplingIntervalMs,
    required this.enableStructuredLogs,
    required this.enableVerbosePipelineLogs,
    required this.recentPlatesLimit,
    required this.maxRecentEventsWindowPerPlate,
    required this.purgeRetentionDays,
    required this.featureFlags,
  });

  factory RuntimeConfig.build({
    double? minFusedConfidence,
    int? dedupeWindowMs,
    String? activeModelId,
    bool? enableDevOverlay,
    bool? enableCharScores,
    int? modelInferenceTimeoutMs,
    int? degradeP95LatencyMs,
    int? degradeFailureWindow,
    bool? allowConcurrentDetect,
    int? samplingIntervalMs,
    bool? enableStructuredLogs,
    bool? enableVerbosePipelineLogs,
    int? recentPlatesLimit,
    int? maxRecentEventsWindowPerPlate,
    int? purgeRetentionDays,
    Map<String, Object?>? featureFlags,
  }) {
    final d = _defaultConfig();
    return RuntimeConfig._(
      minFusedConfidence: minFusedConfidence ?? d.minFusedConfidence,
      dedupeWindowMs: dedupeWindowMs ?? d.dedupeWindowMs,
      activeModelId: activeModelId ?? d.activeModelId,
      enableDevOverlay: enableDevOverlay ?? d.enableDevOverlay,
      enableCharScores: enableCharScores ?? d.enableCharScores,
      modelInferenceTimeoutMs:
          modelInferenceTimeoutMs ?? d.modelInferenceTimeoutMs,
      degradeP95LatencyMs: degradeP95LatencyMs ?? d.degradeP95LatencyMs,
      degradeFailureWindow: degradeFailureWindow ?? d.degradeFailureWindow,
      allowConcurrentDetect:
          allowConcurrentDetect ?? d.allowConcurrentDetect,
      samplingIntervalMs: samplingIntervalMs ?? d.samplingIntervalMs,
      enableStructuredLogs:
          enableStructuredLogs ?? d.enableStructuredLogs,
      enableVerbosePipelineLogs: enableVerbosePipelineLogs ??
          d.enableVerbosePipelineLogs,
      recentPlatesLimit: recentPlatesLimit ?? d.recentPlatesLimit,
      maxRecentEventsWindowPerPlate: maxRecentEventsWindowPerPlate ??
          d.maxRecentEventsWindowPerPlate,
      purgeRetentionDays: purgeRetentionDays ?? d.purgeRetentionDays,
      featureFlags: Map.unmodifiable(
          {...d.featureFlags, ...(featureFlags ?? const {})}),
    );
  }

  RuntimeConfig copyWith({
    double? minFusedConfidence,
    int? dedupeWindowMs,
    String? activeModelId,
    bool? enableDevOverlay,
    bool? enableCharScores,
    int? modelInferenceTimeoutMs,
    int? degradeP95LatencyMs,
    int? degradeFailureWindow,
    bool? allowConcurrentDetect,
    int? samplingIntervalMs,
    bool? enableStructuredLogs,
    bool? enableVerbosePipelineLogs,
    int? recentPlatesLimit,
    int? maxRecentEventsWindowPerPlate,
    int? purgeRetentionDays,
    Map<String, Object?>? featureFlags,
  }) =>
      RuntimeConfig._(
        minFusedConfidence: minFusedConfidence ?? this.minFusedConfidence,
        dedupeWindowMs: dedupeWindowMs ?? this.dedupeWindowMs,
        activeModelId: activeModelId ?? this.activeModelId,
        enableDevOverlay: enableDevOverlay ?? this.enableDevOverlay,
        enableCharScores: enableCharScores ?? this.enableCharScores,
        modelInferenceTimeoutMs:
            modelInferenceTimeoutMs ?? this.modelInferenceTimeoutMs,
        degradeP95LatencyMs:
            degradeP95LatencyMs ?? this.degradeP95LatencyMs,
        degradeFailureWindow:
            degradeFailureWindow ?? this.degradeFailureWindow,
        allowConcurrentDetect:
            allowConcurrentDetect ?? this.allowConcurrentDetect,
        samplingIntervalMs: samplingIntervalMs ?? this.samplingIntervalMs,
        enableStructuredLogs:
            enableStructuredLogs ?? this.enableStructuredLogs,
        enableVerbosePipelineLogs: enableVerbosePipelineLogs ??
            this.enableVerbosePipelineLogs,
        recentPlatesLimit: recentPlatesLimit ?? this.recentPlatesLimit,
        maxRecentEventsWindowPerPlate:
            maxRecentEventsWindowPerPlate ??
                this.maxRecentEventsWindowPerPlate,
        purgeRetentionDays: purgeRetentionDays ?? this.purgeRetentionDays,
        featureFlags: featureFlags == null
            ? this.featureFlags
            : Map.unmodifiable({...this.featureFlags, ...featureFlags}),
      );

  @override
  String toString() =>
      'RuntimeConfig(model=$activeModelId, minConf=$minFusedConfidence, dedupe=${dedupeWindowMs}ms, sample=${samplingIntervalMs}ms)';
}

RuntimeConfig _defaultConfig() => const RuntimeConfig._(
      minFusedConfidence: 0.55,
      dedupeWindowMs: 3000,
      activeModelId: 'tflite_v1_fast',
      enableDevOverlay: false,
      enableCharScores: false,
      modelInferenceTimeoutMs: 250,
      degradeP95LatencyMs: 120,
      degradeFailureWindow: 50,
      allowConcurrentDetect: false,
      samplingIntervalMs: 150, // ~6-7 FPS effective
      enableStructuredLogs: true,
      enableVerbosePipelineLogs: false,
      recentPlatesLimit: 50,
      maxRecentEventsWindowPerPlate: 16,
      purgeRetentionDays: 0, // 0 = unlimited retention (MVP)
      featureFlags: {},
    );

// ---------------------------------------------------------------------------
// Service Interfaces
// ---------------------------------------------------------------------------

/// Exposes access to current config + updates.
abstract interface class RuntimeConfigService {
  RuntimeConfig get current;

  /// Stream of new snapshots *after* they are committed.
  Stream<RuntimeConfig> get updates;

  /// Apply partial overrides; returns new snapshot.
  RuntimeConfig update(
      RuntimeConfig Function(RuntimeConfig current) mutator);

  /// Replace entire snapshot (careful).
  RuntimeConfig replace(RuntimeConfig next);

  /// Reset to defaults (discarding overrides).
  RuntimeConfig reset();

  /// Read arbitrary feature flag (returns null if absent).
  T? flag<T>(String key);
}

// ---------------------------------------------------------------------------
// In-Memory Implementation
// ---------------------------------------------------------------------------

class InMemoryRuntimeConfigService implements RuntimeConfigService {
  RuntimeConfig _current;
  final StreamController<RuntimeConfig> _controller =
      StreamController.broadcast();

  InMemoryRuntimeConfigService._(this._current);

  factory InMemoryRuntimeConfigService.withDefaults() =>
      InMemoryRuntimeConfigService._(_defaultConfig());

  factory InMemoryRuntimeConfigService.seed(RuntimeConfig seed) =>
      InMemoryRuntimeConfigService._(seed);

  @override
  RuntimeConfig get current => _current;

  @override
  Stream<RuntimeConfig> get updates => _controller.stream;

  void _emit(RuntimeConfig next) {
    _current = next;
    _controller.add(next);
  }

  @override
  RuntimeConfig update(
      RuntimeConfig Function(RuntimeConfig current) mutator) {
    final next = mutator(_current);
    if (identical(next, _current)) return _current;
    _emit(next);
    return next;
  }

  @override
  RuntimeConfig replace(RuntimeConfig next) {
    if (identical(_current, next)) return _current;
    _emit(next);
    return next;
  }

  @override
  RuntimeConfig reset() {
    final next = _defaultConfig();
    _emit(next);
    return next;
  }

  @override
  T? flag<T>(String key) {
    final v = _current.featureFlags[key];
    if (v is T) return v;
    return null;
  }

  /// Convenience: update single primitive fields safely.
  void setMinFusedConfidence(double value) => update(
      (c) => c.copyWith(minFusedConfidence: value.clamp(0.0, 1.0).toDouble()));

  void setDedupeWindowMs(int ms) => update(
      (c) => c.copyWith(dedupeWindowMs: ms < 0 ? 0 : ms));

  void setActiveModel(String id) =>
      update((c) => c.copyWith(activeModelId: id));

  void setSamplingIntervalMs(int ms) => update(
      (c) => c.copyWith(samplingIntervalMs: ms < 16 ? 16 : ms));

  void setFlag(String key, Object? value) => update((c) {
        final newFlags = Map<String, Object?>.from(c.featureFlags);
        if (value == null) {
          newFlags.remove(key);
        } else {
          newFlags[key] = value;
        }
        return c.copyWith(featureFlags: newFlags);
      });

  /// Dispose the service (close stream). After disposal, no further updates.
  Future<void> dispose() async {
   await _controller.close();
  }
}

// ---------------------------------------------------------------------------
// Serialization Helpers (Optional Future Persistence)
// ---------------------------------------------------------------------------

/// Serialize config to a plain JSON map (all primitive encodable).
Map<String, Object?> serializeConfig(RuntimeConfig cfg) => {
      'minFusedConfidence': cfg.minFusedConfidence,
      'dedupeWindowMs': cfg.dedupeWindowMs,
      'activeModelId': cfg.activeModelId,
      'enableDevOverlay': cfg.enableDevOverlay,
      'enableCharScores': cfg.enableCharScores,
      'modelInferenceTimeoutMs': cfg.modelInferenceTimeoutMs,
      'degradeP95LatencyMs': cfg.degradeP95LatencyMs,
      'degradeFailureWindow': cfg.degradeFailureWindow,
      'allowConcurrentDetect': cfg.allowConcurrentDetect,
      'samplingIntervalMs': cfg.samplingIntervalMs,
      'enableStructuredLogs': cfg.enableStructuredLogs,
      'enableVerbosePipelineLogs': cfg.enableVerbosePipelineLogs,
      'recentPlatesLimit': cfg.recentPlatesLimit,
      'maxRecentEventsWindowPerPlate': cfg.maxRecentEventsWindowPerPlate,
      'purgeRetentionDays': cfg.purgeRetentionDays,
      'featureFlags': cfg.featureFlags,
    };

/// Deserialize from JSON map (missing fields use defaults).
RuntimeConfig deserializeConfig(Map<String, Object?> json) {
  final d = _defaultConfig();
  T get<T>(String k, T current) {
    final v = json[k];
    if (v is T) return v;
    return current;
  }
  final featureFlags = <String, Object?>{};
  final flagsRaw = json['featureFlags'];
  if (flagsRaw is Map) {
    for (final e in flagsRaw.entries) {
      if (e.key is String) featureFlags[e.key as String] = e.value;
    }
  }
  return d.copyWith(
    minFusedConfidence: get('minFusedConfidence', d.minFusedConfidence),
    dedupeWindowMs: get('dedupeWindowMs', d.dedupeWindowMs),
    activeModelId: get('activeModelId', d.activeModelId),
    enableDevOverlay: get('enableDevOverlay', d.enableDevOverlay),
    enableCharScores: get('enableCharScores', d.enableCharScores),
    modelInferenceTimeoutMs:
        get('modelInferenceTimeoutMs', d.modelInferenceTimeoutMs),
    degradeP95LatencyMs:
        get('degradeP95LatencyMs', d.degradeP95LatencyMs),
    degradeFailureWindow:
        get('degradeFailureWindow', d.degradeFailureWindow),
    allowConcurrentDetect:
        get('allowConcurrentDetect', d.allowConcurrentDetect),
    samplingIntervalMs:
        get('samplingIntervalMs', d.samplingIntervalMs),
    enableStructuredLogs:
        get('enableStructuredLogs', d.enableStructuredLogs),
    enableVerbosePipelineLogs: get(
        'enableVerbosePipelineLogs', d.enableVerbosePipelineLogs),
    recentPlatesLimit: get('recentPlatesLimit', d.recentPlatesLimit),
    maxRecentEventsWindowPerPlate: get(
        'maxRecentEventsWindowPerPlate',
        d.maxRecentEventsWindowPerPlate),
    purgeRetentionDays:
        get('purgeRetentionDays', d.purgeRetentionDays),
    featureFlags: featureFlags,
  );
}

// End of file.