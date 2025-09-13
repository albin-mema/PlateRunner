/// Media Import Service Scaffold
///
/// Purpose:
///   Provide a thin abstraction for selecting an image or video from local
///   storage (gallery / file picker) and feeding synthetic frame descriptors
///   into the recognition pipeline. Because the current pipeline + mock
///   adapter only rely on `FrameDescriptor` metadata (no raw pixel buffers
///   yet), we can simulate frames for imported media until real pixel
///   handling + model preprocessing is added.
///
/// Scope (MVP):
///   - Image import: generate a single synthetic `FrameDescriptor` and feed
///     into the pipeline (treated like a one-off frame).
///   - Video import: iterate over a sampled timeline producing synthetic
///     frame descriptors (frame IDs derived from video name + timestamp).
///   - Provide result summaries (#frames generated / #recognitions observed).
///
/// Non-Goals (Initial):
///   - Actual decoding to obtain pixel buffers.
///   - Frame-accurate timestamps or honoring variable frame rates.
///   - Cross-platform file dialogs beyond what `image_picker` supports.
///   - Web video frame extraction (stubbed).
///
/// Future Enhancements:
///   - Real pixel buffer extraction (ffmpeg / custom plugin).
///   - Configurable sampling by FPS or adaptive scene change detection.
///   - Inject frames directly with pixel data once adapter expects them.
///   - Desktop file picker integration (file_selector).
///
/// Dependencies (declared in pubspec):
///   - image_picker
///   - video_player  (NOTE: video_player does NOT expose raw frame pixels; we
///                     only use it for duration + metadata placeholder).
///
/// Platform Notes:
///   - On web, `image_picker` has limited support; video import may noop.
///   - Gracefully degrade by returning `MediaImportFailure.unsupported`.
///
/// Usage Example:
/// ```dart
/// final media = MediaImportService();
/// final imgResult = await media.importImageAndRun(
///   context: context,
///   pipeline: pipeline,
/// );
/// print('Image import emitted ${imgResult.recognitionsEmitted} recognitions');
///
/// final vidSession = await media.importVideo(
///   context: context,
///   pipeline: pipeline,
///   targetSampleMs: 500,
///   maxFrames: 40,
/// );
/// print('Video processed frames=${vidSession.framesGenerated} recognitions=${vidSession.recognitionsEmitted}');
/// ```
///
/// Integration Detail:
///   - We listen temporarily to `pipeline.events` during media processing to
///     count recognitions caused by imported frames. (This is simplistic and
///     may over-count if the live pipeline is simultaneously running camera
///     frames—recommend pausing live feed during imports.)
///
/// Safety:
///   - Service methods are reentrant but each call sets up its own temporary
///     subscription. Dispose not strictly required; provided for symmetry.
///
/// Author: Initial scaffold.
library media_import_service;

import 'dart:async';



import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// Removed video_player dependency (simulation-only video import)

import 'package:plate_runner/app/pipeline/recognition_pipeline.dart';
import 'package:plate_runner/infrastructure/model/model_adapter.dart';

/// Result wrapper for image import invocation.
sealed class ImageImportResult {
  const ImageImportResult();
}

class ImageImportSuccess extends ImageImportResult {
  final int framesGenerated;
  final int recognitionsEmitted;
  final String? debugLabel;
  const ImageImportSuccess({
    required this.framesGenerated,
    required this.recognitionsEmitted,
    this.debugLabel,
  });

  @override
  String toString() =>
      'ImageImportSuccess(frames=$framesGenerated, recognitions=$recognitionsEmitted, label=$debugLabel)';
}

class ImageImportFailure extends ImageImportResult {
  final String reason;
  final MediaImportFailureCode code;
  const ImageImportFailure(this.reason, this.code);

  @override
  String toString() => 'ImageImportFailure(code=$code, reason="$reason")';
}

enum MediaImportFailureCode {
  cancelled,
  unsupported,
  pipelineNotRunning,
  pickerError,
  internal,
}

/// Session summary for a processed video.
class VideoImportSession {
  final String sourceName;
  final Duration videoDuration;
  final int framesGenerated;
  final int recognitionsEmitted;
  final int sampledEveryMs;
  final bool truncated;
  const VideoImportSession({
    required this.sourceName,
    required this.videoDuration,
    required this.framesGenerated,
    required this.recognitionsEmitted,
    required this.sampledEveryMs,
    required this.truncated,
  });

  @override
  String toString() =>
      'VideoImportSession(src=$sourceName dur=${videoDuration.inMilliseconds}ms '
      'frames=$framesGenerated recognitions=$recognitionsEmitted every=${sampledEveryMs}ms truncated=$truncated)';
}

/// Service facade.
class MediaImportService {
  final ImagePicker _picker;

  MediaImportService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  bool get isVideoSupported {
    // Simulation now works on all platforms (no native decoder required yet).
    return true;
  }

  /// Imports a single image and pushes one synthetic frame into the pipeline.
  /// Returns result with counts (framesGenerated=1 if successful).
  Future<ImageImportResult> importImageAndRun({
    required BuildContext context,
    required RecognitionPipeline pipeline,
    String? debugLabel,
  }) async {
    if (pipeline.state != PipelineState.running) {
      return const ImageImportFailure(
        'Pipeline must be running to import image',
        MediaImportFailureCode.pipelineNotRunning,
      );
    }

    try {
      final XFile? picked =
          await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        return const ImageImportFailure(
          'User cancelled image pick',
          MediaImportFailureCode.cancelled,
        );
      }

      final frameId = _buildImportFrameId('img', picked.name);
      final subCounter = _RecognitionCounter(pipeline);
      subCounter.start();

      // Create a synthetic frame descriptor. Real implementation later will parse
      // image dimensions; for now we fabricate typical dimensions.
      final frame = FrameDescriptor(
        id: frameId,
        epochMs: DateTime.now().millisecondsSinceEpoch,
        width: 320,
        height: 192,
      );
      pipeline.ingestImportedFrame(frame);

      // Allow pipeline loop to process (mock adapter latency ~35ms). We await one event or timeout.
      await subCounter.waitBrief(Duration(milliseconds: 250));

      final emitted = subCounter.stopAndCount();
      return ImageImportSuccess(
        framesGenerated: 1,
        recognitionsEmitted: emitted,
        debugLabel: debugLabel ?? picked.name,
      );
    } catch (e) {
      return ImageImportFailure(
        'Picker error: $e',
        MediaImportFailureCode.pickerError,
      );
    }
  }

  /// Imports a video and samples frames at `targetSampleMs` interval (approx).
  /// For each sampled timestamp, a synthetic FrameDescriptor is generated and fed.
  ///
  /// NOTE: `video_player` does not expose raw pixel frames. This scaffold
  /// simply uses video duration metadata to synthesize frames. When real frame
  /// extraction is added, replace `_simulateVideoFrames`.
  Future<VideoImportSession> importVideo({
    required BuildContext context,
    required RecognitionPipeline pipeline,
    int targetSampleMs = 500,
    int maxFrames = 200,
  }) async {
    if (pipeline.state != PipelineState.running) {
      return const VideoImportSession(
        sourceName: 'N/A',
        videoDuration: Duration.zero,
        framesGenerated: 0,
        recognitionsEmitted: 0,
        sampledEveryMs: 0,
        truncated: false,
      );
    }
    if (!isVideoSupported) {
      return const VideoImportSession(
        sourceName: 'UNSUPPORTED',
        videoDuration: Duration.zero,
        framesGenerated: 0,
        recognitionsEmitted: 0,
        sampledEveryMs: 0,
        truncated: false,
      );
    }

    XFile? file;
    try {
      file = await _picker.pickVideo(source: ImageSource.gallery);
    } catch (e) {
      return VideoImportSession(
        sourceName: 'ERROR',
        videoDuration: Duration.zero,
        framesGenerated: 0,
        recognitionsEmitted: 0,
        sampledEveryMs: targetSampleMs,
        truncated: false,
      );
    }

    if (file == null) {
      return VideoImportSession(
        sourceName: 'CANCELLED',
        videoDuration: Duration.zero,
        framesGenerated: 0,
        recognitionsEmitted: 0,
        sampledEveryMs: targetSampleMs,
        truncated: false,
      );
    }

    // Simulate video duration (remove real controller until pixel extraction added).
    final simulatedDuration = Duration(
      milliseconds: targetSampleMs * maxFrames > 60000
          ? 60000
          : targetSampleMs * maxFrames,
    );

// (Controller removed) using purely simulated duration until native frame extraction implemented.

    // Simulated duration (fallback) since we skipped actual controller load.
// simulatedDuration already defined above
    final subCounter = _RecognitionCounter(pipeline)..start();

    final framesGenerated = _simulateVideoFrames(
      pipeline: pipeline,
      sourceName: file.name,
      duration: simulatedDuration,
      targetSampleMs: targetSampleMs,
      maxFrames: maxFrames,
    );

    // Allow last batch to process.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final emitted = subCounter.stopAndCount();

    return VideoImportSession(
      sourceName: file.name,
      videoDuration: simulatedDuration,
      framesGenerated: framesGenerated,
      recognitionsEmitted: emitted,
      sampledEveryMs: targetSampleMs,
      truncated: framesGenerated >= maxFrames,
    );
  }

  // ---- Internal Helpers ----

  int _simulateVideoFrames({
    required RecognitionPipeline pipeline,
    required String sourceName,
    required Duration duration,
    required int targetSampleMs,
    required int maxFrames,
  }) {
    final totalMs = duration.inMilliseconds;
    if (targetSampleMs <= 0) return 0;
    int frames = 0;
    for (int t = 0; t < totalMs; t += targetSampleMs) {
      if (frames >= maxFrames) break;
      final frameId = _buildImportFrameId('vid', '$sourceName@$t');
      final w = 320 + (frames % 3) * 16;
      final h = 192 + (frames % 2) * 16;
      pipeline.ingestImportedFrame(
        FrameDescriptor(
          id: frameId,
          epochMs: DateTime.now().millisecondsSinceEpoch + frames,
          width: w,
          height: h,
        ),
      );
      frames++;
    }
    return frames;
  }

  String _buildImportFrameId(String kind, String raw) {
    // Stable-ish hash for reproducibility in mock adapter output.
    final h = raw.hashCode ^ (kind.hashCode << 5);
    final rndPart = (h & 0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'import_${kind}_$rndPart';
  }
}

/// Helper that counts recognitions emitted while active.
class _RecognitionCounter {
  final RecognitionPipeline pipeline;
  StreamSubscription<PipelineRecognition>? _sub;
  int _count = 0;
  Completer<void>? _firstEventCompleter;

  _RecognitionCounter(this.pipeline);

  void start() {
    _firstEventCompleter = Completer<void>();
    _sub = pipeline.events.listen((_) {
      _count++;
      if (!(_firstEventCompleter?.isCompleted ?? true)) {
        _firstEventCompleter?.complete();
      }
    });
  }

  Future<void> waitBrief(Duration timeout) async {
    try {
      await _firstEventCompleter?.future
          .timeout(timeout, onTimeout: () => null);
    } catch (_) {
      // Ignore.
    }
  }

  int stopAndCount() {
    _sub?.cancel();
    _sub = null;
    return _count;
  }
}

/// Utility: Quick helper for random sampling (future use).
// _randInRange removed (unused)
