import 'dart:async';

import 'package:logging/logging.dart';

import '../domain/entities/analysis_result.dart';
import '../domain/entities/photo.dart';
import 'ai_service.dart';
import 'model_configs/model_configs.dart';
import 'worker_pool.dart';

/// ONNX Runtime-backed [AiService].
///
/// Thin orchestration on top of [WorkerPool]:
///   * [warmup] / [analyze] / [dispose] are direct pass-throughs.
///   * [analyzeAll] adds bounded-concurrency fan-out — one in-flight
///     request per worker, results streamed as they complete, first
///     per-photo error surfaced to the listener so the UI can show
///     *what* went wrong instead of a generic "0 results" message.
class OnnxAiService implements AiService {
  OnnxAiService({
    required ModelConfig model,
    int? workerCount,
  }) : _pool = WorkerPool(model: model, workerCount: workerCount);

  final WorkerPool _pool;
  static final _log = Logger('OnnxAiService');

  @override
  Future<void> warmup() => _pool.warmup();

  @override
  Future<AnalysisResult> analyze(Photo photo) => _pool.dispatch(photo);

  @override
  Stream<AnalysisResult> analyzeAll(List<Photo> photos) async* {
    if (photos.isEmpty) return;
    await _pool.warmup();

    final controller = StreamController<AnalysisResult>();
    final concurrency = _pool.workerCount;
    var nextIndex = 0;
    var inFlight = 0;
    var closed = false;
    Object? firstError;
    StackTrace? firstStack;

    void scheduleMore() {
      // Top up to [concurrency] futures in flight, dispatching the
      // next pending photo whenever a worker becomes free.
      while (inFlight < concurrency && nextIndex < photos.length) {
        final photo = photos[nextIndex++];
        inFlight++;
        _pool.dispatch(photo).then(
          (r) {
            if (!closed) controller.add(r);
          },
          onError: (Object e, StackTrace st) {
            _log.warning('inference failed', e, st);
            firstError ??= e;
            firstStack ??= st;
          },
        ).whenComplete(() {
          inFlight--;
          final allDone = nextIndex >= photos.length && inFlight == 0;
          if (allDone && !closed) {
            closed = true;
            if (firstError != null) {
              controller.addError(firstError!, firstStack);
            }
            controller.close();
          } else {
            scheduleMore();
          }
        });
      }
    }

    scheduleMore();
    yield* controller.stream;
  }

  @override
  Future<void> dispose() => _pool.dispose();
}
