// PlateRunner main entrypoint - wired to RecognitionPipeline + (temporary) FakeCameraService. (Web build friendly: native TFLite deps temporarily removed; using mock adapter & fake camera.)
// NOTE: Real camera plugin integration removed temporarily; using FakeCameraService stub.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:plate_runner/shared/config/runtime_config.dart';
import 'package:plate_runner/ui/theme/app_theme.dart';
import 'package:plate_runner/app/pipeline/recognition_pipeline.dart';
import 'package:plate_runner/infrastructure/model/model_adapter.dart';
import 'package:plate_runner/infrastructure/model/model_adapter.dart' show FrameDescriptor;
import 'package:plate_runner/infrastructure/camera/camera_service.dart';
import 'package:plate_runner/infrastructure/persistence/memory_repository.dart';
import 'package:plate_runner/infrastructure/media/media_import_service.dart';

//
// TODO(camera): Replace placeholder preview with real CameraPreview from plugin.
// TODO(model): Swap DeterministicMockAdapter for real TFLite adapter when ready.
// TODO(overlay): Render bounding boxes + dev overlay metrics & bounding boxes.
//

// Global runtime config service (DI placeholder).
final InMemoryRuntimeConfigService _configService =
    InMemoryRuntimeConfigService.withDefaults();

void main() {
  runApp(PlateRunnerApp(configService: _configService));
}

class PlateRunnerApp extends StatelessWidget {
  final InMemoryRuntimeConfigService configService;
  const PlateRunnerApp({super.key, required this.configService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RuntimeConfig>(
      stream: configService.updates,
      initialData: configService.current,
      builder: (context, snapshot) {
        final cfg = snapshot.data ?? configService.current;
        final isDevEnv =
            const String.fromEnvironment('APP_ENV', defaultValue: 'prod')
                    .toLowerCase() ==
                'dev';
        final showDevBanner = isDevEnv || cfg.enableDevOverlay;

        final app = MaterialApp(
          title: 'PlateRunner',
          debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          home: LiveScanPage(
            config: cfg,
            configService: configService,
          ),
        );

        if (!showDevBanner) return app;
        return Banner(
          location: BannerLocation.topStart,
          message: 'DEV',
          color: Colors.deepOrange.withValues(alpha: 0.85),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
          child: app,
        );
      },
    );
  }
}

/// Removed real permission delegate (permission_handler dependency) while using FakeCameraService.
/// When reintroducing real camera integration, restore a permission delegate implementation.

/// Live scan prototype screen using RecognitionPipeline + mock adapter + camera service.
/// Fallback to synthetic frames if camera init/start fails or permission denied.
class LiveScanPage extends StatefulWidget {
  final RuntimeConfig config;
  final RuntimeConfigService configService;
  const LiveScanPage({
    super.key,
    required this.config,
    required this.configService,
  });

  @override
  State<LiveScanPage> createState() => _LiveScanPageState();
}

class _LiveScanPageState extends State<LiveScanPage> {
  late RecognitionPipeline _pipeline;
  late InMemoryPlateRepository _repo;
  late MediaImportService _mediaService;
  StreamSubscription<PipelineUpsert>? _planSub;
  CameraService? _cameraService;
  StreamSubscription<FrameDescriptor>? _cameraFrameSub;
  StreamSubscription<CameraServiceEvent>? _cameraEventSub;

  bool _running = false;
  bool _cameraActive = false;
  bool _useSyntheticFallback = false;
  bool _initializingCamera = false;

  final List<_PlateHit> _recent = [];
  static const int _recentMax = 10;

  int _syntheticFrameCounter = 0;
  bool _disposed = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _pipeline = RecognitionPipeline(
      adapter: DeterministicMockAdapter(),
      configService: widget.configService,
      logSink: (e) {
        if (!mounted) return;
        if (widget.config.enableStructuredLogs) {
          // ignore: avoid_print
          print('[PIPELINE] $e');
        }
      },
    );
    _mediaService = MediaImportService();
    // In-memory repository + attach to pipeline plan stream
    _repo = InMemoryPlateRepository();
    _planSub = _repo.attachToPipelinePlans(_pipeline.plans);

    _pipeline.events.listen((rec) {
      if (!mounted) return;
      setState(() {
        _recent.insert(
          0,
          _PlateHit(
            plate: rec.event.plate.value,
            confidence: rec.event.confidence.value,
          ),
        );
        if (_recent.length > _recentMax) {
          _recent.removeRange(_recentMax, _recent.length);
        }
      });
    });
  }

  Future<void> _initCameraIfNeeded() async {
    if (_cameraService != null || _initializingCamera) return;
    _initializingCamera = true;
    // Using FakeCameraService stub (no real permissions / hardware).
    final service = FakeCameraService(
      config: const CameraConfig(
        targetFps: 30,
        minFrameIntervalMs: 0,
      ),
    );
    _cameraService = service;

    _cameraEventSub = service.events.listen((evt) {
      if (!mounted) return;
      if (evt is CameraError) {
        setState(() {
          _cameraError = '${evt.code}: ${evt.message}';
          _useSyntheticFallback = true;
          _cameraActive = false;
        });
        _teardownCameraStream();
        if (_running && !_disposed) {
          _scheduleSyntheticFrames(); // auto fallback
        }
      } else if (evt is CameraStarted) {
        setState(() {
          _cameraActive = true;
          _cameraError = null;
        });
      } else if (evt is CameraStopped) {
        setState(() {
            _cameraActive = false;
        });
      }
    });

    try {
      await service.initialize();
      await service.start();
      _cameraFrameSub = service.frames.listen((f) {
        _pipeline.feedFrame(f);
      });
      setState(() {
        _cameraActive = true;
        _useSyntheticFallback = false;
        _cameraError = null;
      });
    } catch (e) {
      setState(() {
        _cameraError = 'Camera init failure: $e';
        _useSyntheticFallback = true;
        _cameraActive = false;
      });
      _teardownCameraStream();
    } finally {
      _initializingCamera = false;
    }
  }

  void _teardownCameraStream() {
    _cameraFrameSub?.cancel();
    _cameraFrameSub = null;
  }

  @override
  void didUpdateWidget(covariant LiveScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Could react to config changes (sampling interval, etc.) here.
  }

  Future<void> _toggleRun() async {
    if (_running) {
      await _pipeline.stop();
      await _cameraService?.stop();
      setState(() {
        _running = false;
        _cameraActive = false;
      });
      return;
    }
    await _pipeline.start();
    setState(() {
      _running = true;
    });

    await _initCameraIfNeeded();

    // Using fake camera; only fall back to synthetic generator if fake camera not active.
    if (!_cameraActive) {
      _useSyntheticFallback = true;
      _scheduleSyntheticFrames();
    }
  }

  void _scheduleSyntheticFrames() {
    Future.doWhile(() async {
      if (!_running || _disposed || !_useSyntheticFallback) return false;
      _feedSyntheticFrame();
      await Future<void>.delayed(
        Duration(milliseconds: widget.config.samplingIntervalMs),
      );
      return _running && _useSyntheticFallback;
    });
  }

  void _feedSyntheticFrame() {
    final id = 'synthetic_${_syntheticFrameCounter++}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final frame = FrameDescriptor(
      id: id,
      epochMs: now,
      width: 320,
      height: 192,
    );
    _pipeline.feedFrame(frame);
  }

  Future<void> _importImage() async {
    if (!_running) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start pipeline first')),
      );
      return;
    }
    final res = await _mediaService.importImageAndRun(
      context: context,
      pipeline: _pipeline,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.toString())),
    );
  }

  Future<void> _importVideo() async {
    if (!_running) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start pipeline first')),
      );
      return;
    }
    final session = await _mediaService.importVideo(
      context: context,
      pipeline: _pipeline,
      targetSampleMs: 600,
      maxFrames: 120,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(session.toString())),
    );
  }

  void _showImportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Import Image'),
              onTap: () async {
                Navigator.pop(ctx);
                await _importImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie),
              title: const Text('Import Video'),
              onTap: () async {
                Navigator.pop(ctx);
                await _importVideo();
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Color _confidenceColor(double c) {
    if (c >= 0.80) return Colors.green.shade600;
    if (c >= 0.65) return Colors.teal.shade600;
    if (c >= 0.55) return Colors.amber.shade700;
    return Colors.red.shade700;
  }

  @override
  void dispose() {
    _disposed = true;
    _teardownCameraStream();
    _cameraEventSub?.cancel();
    _cameraService?.dispose();
    _planSub?.cancel();
    _repo.dispose();
    _pipeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;

    final previewStatus = _cameraActive
        ? 'Camera Active'
        : _useSyntheticFallback
            ? 'Synthetic Feed'
            : _initializingCamera
                ? 'Initializing...'
                : (_cameraError != null ? 'Camera Error' : 'Idle');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Scan (Prototype)'),
        actions: [
          Tooltip(
            message:
                'minConf ${cfg.minFusedConfidence.toStringAsFixed(2)} • dedupe ${cfg.dedupeWindowMs}ms',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Center(
                child: Text(
                  'Cfg',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview placeholder (replace with actual CameraPreview controller widget).
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Text(
                  _running
                      ? '$previewStatus\n(placeholder preview)'
                      : 'Preview stopped\n(placeholder)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white70),
                ),
              ),
            ),
          ),
          if (_cameraError != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _cameraError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Plates',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: _recent.isEmpty
                ? Center(
                    child: Text(
                      'No detections yet',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemBuilder: (ctx, i) {
                      final hit = _recent[i];
                      return Chip(
                        backgroundColor:
                            _confidenceColor(hit.confidence).withOpacity(0.15),
                        label: Text(
                          '${hit.plate} ${(hit.confidence * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: _confidenceColor(hit.confidence),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: _recent.length,
                  ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Pipeline: ${_running ? 'RUNNING' : 'STOPPED'}\n'
                    'Source: ${_cameraActive ? 'Camera' : (_useSyntheticFallback ? 'Synthetic' : 'None')}'
                    '${_cameraError != null ? '\nCamera Error: $_cameraError' : ''}\n'
                    'Adapter: ${cfg.activeModelId}\n'
                    'Press Start to ${_running ? 'stop' : 'begin'} processing.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<PipelineStats>(
                    stream: _pipeline.stats,
                    builder: (context, snapshot) {
                      final s = snapshot.data;
                      if (s == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DefaultTextStyle(
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall!
                              .copyWith(
                                color: Colors.white70,
                                fontFamily: 'monospace',
                              ),
                          child: Builder(
                            builder: (_) {
                              final repoStats = _repo.stats();
                              return Text(
                                'frames ${s.framesOffered}/${s.framesSampleAccepted}  '
                                'inf ${s.inferenceCount}  raw ${s.rawDetections}  emit ${s.recognitionsEmitted}\n'
                                'lat ms avg:${s.inferenceLatencyAvgMs} max:${s.inferenceLatencyMaxMs}\n'
                                'plates ${repoStats.$1} recs ${repoStats.$2}',
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFabRow(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildFabRow(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'run',
          onPressed: _toggleRun,
          icon: Icon(_running ? Icons.stop : Icons.play_arrow),
          label: Text(_running ? 'Stop' : 'Start'),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'import',
          onPressed: _showImportSheet,
          icon: const Icon(Icons.file_open),
          label: const Text('Import'),
        ),
      ],
    );
  }
}

class _PlateHit {
  final String plate;
  final double confidence;
  _PlateHit({required this.plate, required this.confidence});
}
