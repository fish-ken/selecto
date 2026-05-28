import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

import '../domain/entities/analysis_result.dart';
import '../domain/entities/photo.dart';
import 'isolate_messages.dart';
import 'isolate_worker.dart';

/// Manages N worker isolates that all hold the same ONNX model.
/// Distributes single inference requests round-robin and resolves the
/// results back to per-request [Completer]s.
///
/// Owned exclusively by [OnnxAiService]. The pool's API surface is
/// deliberately minimal:
///   * [warmup] — spawn isolates and wait for their handshakes.
///   * [dispatch] — fire off one inference, get a [Future].
///   * [dispose] — tear down workers and ports.
///
/// The fan-out logic that `analyzeAll` needs (bounded concurrency,
/// streamed results, first-error surfacing) lives one layer up in
/// [OnnxAiService] — keeping the pool itself focused on isolate
/// plumbing.
///
/// Invariants:
///   * Each worker owns exactly one [OrtSession]. Sessions are NOT
///     thread-safe — never share or move them.
///   * Workers spawn during [warmup] and stay alive until [dispose].
///   * Every in-flight request's [Completer] is held in [_pending]
///     until a matching [InferenceSuccess] / [InferenceError] arrives.
class WorkerPool {
  WorkerPool({
    required this.modelPath,
    int? workerCount,
  }) : workerCount = workerCount ?? _defaultWorkerCount();

  final String modelPath;
  final int workerCount;

  static final _log = Logger('WorkerPool');

  static int _defaultWorkerCount() {
    // Inference is CPU-heavy. Leave one core free for the UI thread +
    // GPU compositor, but cap at 8 to keep memory under control.
    final cores = Platform.numberOfProcessors;
    return (cores - 1).clamp(1, 8);
  }

  // ───── runtime state ────────────────────────────────────────────────
  final List<SendPort> _commandPorts = [];
  final Map<int, Completer<AnalysisResult>> _pending = {};
  ReceivePort? _replyPort;
  int _nextRequestId = 0;
  int _rrCursor = 0;

  final Completer<void> _allReady = Completer<void>();
  Completer<void>? _warmingUp;
  bool _ready = false;

  /// Spawn all workers and wait for each to handshake. Idempotent and
  /// safe to call from multiple sites in parallel — concurrent callers
  /// all await the same in-flight warmup.
  Future<void> warmup() async {
    if (_ready) return;
    if (_warmingUp != null) return _warmingUp!.future;
    final c = Completer<void>();
    _warmingUp = c;
    try {
      await _spawnWorkers();
      _ready = true;
      c.complete();
    } catch (e, st) {
      c.completeError(e, st);
      _warmingUp = null;
      rethrow;
    }
  }

  Future<void> _spawnWorkers() async {
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

    // Each worker sends [WorkerReady] when it's done loading the model.
    // [_onWorkerMessage] completes [_allReady] once every worker has
    // checked in.
    await _allReady.future;
    _log.info('AI pool ready — $workerCount workers');
  }

  void _onWorkerMessage(Object? msg) {
    switch (msg) {
      case WorkerReady(:final commandPort):
        _commandPorts.add(commandPort);
        if (_commandPorts.length == workerCount && !_allReady.isCompleted) {
          _allReady.complete();
        }

      case InferenceSuccess(
            :final id,
            :final photoCacheKey,
            :final qualityScore,
            :final sharpnessScore,
            :final faceCount,
            :final hasBlink,
          ):
        _pending.remove(id)?.complete(
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
        _pending.remove(id)?.completeError(StateError(error));

      default:
        _log.warning('unexpected worker message: $msg');
    }
  }

  /// Dispatch one inference request to a worker (round-robin). Returns a
  /// future that resolves with the [AnalysisResult] or errors with the
  /// worker-reported failure.
  Future<AnalysisResult> dispatch(Photo photo) async {
    await warmup();
    final id = _nextRequestId++;
    final port = _commandPorts[_rrCursor++ % _commandPorts.length];
    final c = Completer<AnalysisResult>();
    _pending[id] = c;
    port.send(
      InferenceRequest(
        id: id,
        // `decodablePath` is the cached JPEG for RAW files; the file
        // itself for normal JPEG/PNG/etc. See lib/domain/entities/photo.dart.
        photoPath: photo.decodablePath,
        photoCacheKey: photo.cacheKey,
      ),
    );
    return c.future;
  }

  /// Tear down workers + ports. The pool can't be re-warmed after
  /// disposal — construct a fresh instance instead.
  Future<void> dispose() async {
    _replyPort?.close();
    _commandPorts.clear();
    _pending.clear();
    _ready = false;
    _warmingUp = null;
  }
}
