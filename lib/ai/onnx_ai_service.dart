import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

import '../domain/entities/analysis_result.dart';
import '../domain/entities/photo.dart';
import 'ai_service.dart';
import 'isolate_messages.dart';
import 'isolate_worker.dart';

/// Bounded worker pool. Spawns N isolates, each with its own OrtSession.
/// Distributes requests round-robin and back-pressures via a bounded
/// pending queue so the UI never gets ahead of inference.
class OnnxAiService implements AiService {
  OnnxAiService({
    required this.modelPath,
    int? workerCount,
  }) : workerCount = workerCount ?? _defaultWorkerCount();

  final String modelPath;
  final int workerCount;

  final _log = Logger('OnnxAiService');
  final List<SendPort> _commandPorts = [];
  final Map<int, Completer<AnalysisResult>> _pending = {};
  ReceivePort? _replyPort;
  int _nextRequestId = 0;
  int _rrCursor = 0;
  bool _initialized = false;
  Completer<void>? _initing;

  static int _defaultWorkerCount() {
    // Inference is CPU-heavy; leave one core for UI + GPU compositor.
    final cores = Platform.numberOfProcessors;
    return (cores - 1).clamp(1, 8);
  }

  @override
  Future<void> warmup() => _ensureInit();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    if (_initing != null) return _initing!.future;
    final c = Completer<void>();
    _initing = c;
    try {
      await _spawnAll();
      _initialized = true;
      c.complete();
    } catch (e, st) {
      c.completeError(e, st);
      _initing = null;
      rethrow;
    }
  }

  Future<void> _spawnAll() async {
    final reply = ReceivePort();
    _replyPort = reply;
    reply.listen(_onWorkerMessage);

    for (var i = 0; i < workerCount; i++) {
      await Isolate.spawn<WorkerInit>(
        aiWorkerEntry,
        WorkerInit(modelAssetPath: modelPath, replyPort: reply.sendPort),
        debugName: 'ai-worker-$i',
      );
    }

    // Wait for all workers to announce themselves.
    while (_commandPorts.length < workerCount) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _log.info('AI pool ready — $workerCount workers');
  }

  void _onWorkerMessage(Object? msg) {
    switch (msg) {
      case WorkerReady(:final commandPort):
        _commandPorts.add(commandPort);
      case InferenceSuccess(
          :final id,
          :final photoCacheKey,
          :final qualityScore,
          :final sharpnessScore,
          :final faceCount,
          :final hasBlink,
        ):
        final c = _pending.remove(id);
        c?.complete(
          AnalysisResult(
            photoCacheKey: photoCacheKey,
            qualityScore: qualityScore,
            sharpnessScore: sharpnessScore,
            faceCount: faceCount,
            hasBlink: hasBlink,
            computedAt: DateTime.now(),
          ),
        );
      case InferenceError(:final id, :final error):
        final c = _pending.remove(id);
        c?.completeError(StateError(error));
      default:
        _log.warning('unexpected worker message: $msg');
    }
  }

  @override
  Future<AnalysisResult> analyze(Photo photo) async {
    await _ensureInit();
    final id = _nextRequestId++;
    final port = _commandPorts[_rrCursor++ % _commandPorts.length];
    final c = Completer<AnalysisResult>();
    _pending[id] = c;
    port.send(
      InferenceRequest(
        id: id,
        photoPath: photo.path,
        photoCacheKey: photo.cacheKey,
      ),
    );
    return c.future;
  }

  @override
  Stream<AnalysisResult> analyzeAll(List<Photo> photos) async* {
    if (photos.isEmpty) return;
    await _ensureInit();

    // Bounded concurrency = pool size. As one finishes, dispatch the next.
    final controller = StreamController<AnalysisResult>();
    var index = 0;
    var inFlight = 0;
    var closed = false;

    void dispatchNext() {
      while (inFlight < workerCount && index < photos.length) {
        final photo = photos[index++];
        inFlight++;
        analyze(photo).then((r) {
          inFlight--;
          if (!closed) controller.add(r);
          if (index >= photos.length && inFlight == 0 && !closed) {
            closed = true;
            controller.close();
          } else {
            dispatchNext();
          }
        }, onError: (Object e, StackTrace st) {
          inFlight--;
          _log.warning('inference failed', e, st);
          if (index >= photos.length && inFlight == 0 && !closed) {
            closed = true;
            controller.close();
          } else {
            dispatchNext();
          }
        });
      }
    }

    dispatchNext();
    yield* controller.stream;
  }

  @override
  Future<void> dispose() async {
    _replyPort?.close();
    _commandPorts.clear();
    _pending.clear();
    _initialized = false;
    _initing = null;
  }
}
