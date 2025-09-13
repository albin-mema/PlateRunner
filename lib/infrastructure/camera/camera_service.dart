/// Camera Service (Temporary Stub - No External Plugin)
///
/// This simplified file removes the real `camera` plugin dependency for now
/// and keeps only abstractions plus a `FakeCameraService` that emits synthetic
/// frames. It allows the rest of the pipeline & UI to progress without
/// platform integration friction.
///
/// When the real camera integration is reinstated:
///  - Reintroduce a `PluginCameraService` implementation (see previous scaffold)
///  - Keep the interface & event contracts stable where possible
///
/// Provided:
///  - CameraConfig
///  - CameraPermissionDelegate (interface only; real impl defined elsewhere)
///  - CameraService interface
///  - Event sealed classes
///  - FakeCameraService (deterministic synthetic frame stream)
///
/// Used By:
///  - lib/main.dart (LiveScanPage) for camera abstraction
///  - Future tests can directly use FakeCameraService
///
/// References:
///  - lib/app/pipeline/recognition_pipeline.dart
///  - lib/infrastructure/model/model_adapter.dart (FrameDescriptor)
library camera_service;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:plate_runner/infrastructure/model/model_adapter.dart'
    show FrameDescriptor, FramePixelFormat;

/// Immutable configuration for camera acquisition (even in stub form).
@immutable
class CameraConfig {
  /// Advisory target FPS (used only for documentation / future real impl).
  final int targetFps;

  /// Minimum interval (ms) between emitted frames (throttle inside service).
  final int minFrameIntervalMs;

  /// Max buffered frames (placeholder for future backpressure logic).
  final int maxBuffer;

  /// Whether to drop oldest frame when buffer full (future real impl).
  final bool dropOldest;

  const CameraConfig({
    this.targetFps = 30,
    this.minFrameIntervalMs = 0,
    this.maxBuffer = 8,
    this.dropOldest = true,
  });

  CameraConfig copyWith({
    int? targetFps,
    int? minFrameIntervalMs,
    int? maxBuffer,
    bool? dropOldest,
  }) =>
      CameraConfig(
        targetFps: targetFps ?? this.targetFps,
        minFrameIntervalMs: minFrameIntervalMs ?? this.minFrameIntervalMs,
        maxBuffer: maxBuffer ?? this.maxBuffer,
        dropOldest: dropOldest ?? this.dropOldest,
      );
}

/// Permission delegate abstraction (real impl lives outside this file).
abstract interface class CameraPermissionDelegate {
  Future<bool> ensureGranted();
}

/// Base class for camera service events.
sealed class CameraServiceEvent {
  const CameraServiceEvent();
}

class CameraInitialized extends CameraServiceEvent {
  final String cameraName;
  const CameraInitialized(this.cameraName);
}

class CameraStarted extends CameraServiceEvent {
  const CameraStarted();
}

class CameraStopped extends CameraServiceEvent {
  const CameraStopped();
}

class CameraError extends CameraServiceEvent {
  final String code;
  final String message;
  final Object? cause;
  const CameraError({
    required this.code,
    required this.message,
    this.cause,
  });

  @override
  String toString() =>
      'CameraError(code=$code, message=$message${cause != null ? ', cause=$cause' : ''})';
}

/// Public interface for camera service abstraction.
abstract interface class CameraService {
  /// Stream of lightweight frame descriptors (metadata only).
  Stream<FrameDescriptor> get frames;

  /// Lifecycle & error events.
  Stream<CameraServiceEvent> get events;

  bool get isInitialized;
  bool get isRunning;
  CameraConfig get config;

  Future<void> initialize({String? cameraId});
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Deterministic synthetic camera producing frames at a fixed interval.
/// Intended for development & testing until real camera integration returns.
class FakeCameraService implements CameraService {
  final CameraConfig _config;
  final Duration frameInterval;
  final int maxFrames;
  final StreamController<FrameDescriptor> _frameCtrl =
      StreamController.broadcast();
  final StreamController<CameraServiceEvent> _eventCtrl =
      StreamController.broadcast();

  bool _running = false;
  bool _initialized = false;
  bool _disposed = false;
  int _emitted = 0;
  int _lastEmitTs = 0;

  FakeCameraService({
    CameraConfig? config,
    this.frameInterval = const Duration(milliseconds: 50),
    this.maxFrames = 500,
  }) : _config = config ?? const CameraConfig();

  // ---- CameraService implementation ----

  @override
  Stream<FrameDescriptor> get frames => _frameCtrl.stream;

  @override
  Stream<CameraServiceEvent> get events => _eventCtrl.stream;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isRunning => _running;

  @override
  CameraConfig get config => _config;

  @override
  Future<void> initialize({String? cameraId}) async {
    _ensureNotDisposed();
    if (_initialized) return;
    // Simulate async initialization latency.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    _initialized = true;
    _eventCtrl.add(CameraInitialized('fake_camera'));
  }

  @override
  Future<void> start() async {
    _ensureNotDisposed();
    if (!_initialized) await initialize();
    if (_running) return;
    _running = true;
    _eventCtrl.add(const CameraStarted());

    Future.doWhile(() async {
      if (!_running || _disposed) return false;
      if (_emitted >= maxFrames) {
        await stop();
        return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;

      // Throttle based on minFrameIntervalMs configuration.
      if (_config.minFrameIntervalMs > 0 &&
          (now - _lastEmitTs) < _config.minFrameIntervalMs) {
        await Future<void>.delayed(
            Duration(milliseconds: _config.minFrameIntervalMs));
        return _running;
      }
      _lastEmitTs = now;

      final frame = FrameDescriptor(
        id: 'fake_${_emitted++}',
        epochMs: now,
        width: 320,
        height: 192,
        format: FramePixelFormat.yuv420,
      );
      if (!_frameCtrl.isClosed) {
        _frameCtrl.add(frame);
      }
      await Future<void>.delayed(frameInterval);
      return _running;
    });
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _eventCtrl.add(const CameraStopped());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    await _frameCtrl.close();
    await _eventCtrl.close();
    _disposed = true;
  }

  // ---- Internal helpers ----

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('FakeCameraService disposed');
    }
  }
}

/// Utility: quick no-op permission delegate for tests / dev.
class AlwaysGrantedPermissionDelegate implements CameraPermissionDelegate {
  const AlwaysGrantedPermissionDelegate();
  @override
  Future<bool> ensureGranted() async => true;
}

/// Utility: permission delegate that always denies (for UI testing).
class AlwaysDeniedPermissionDelegate implements CameraPermissionDelegate {
  const AlwaysDeniedPermissionDelegate();
  @override
  Future<bool> ensureGranted() async => false;
}