import '../domain/entities/analysis_result.dart';
import '../domain/entities/photo.dart';

/// The single public entry point for AI-driven photo analysis.
///
/// Everything outside `lib/ai/` (UI, Riverpod providers, use cases) talks
/// to the AI subsystem through this interface and nothing else. That
/// keeps the FFI / isolate / ONNX-specific code from leaking into the
/// rest of the app and makes the implementation trivially swappable
/// (mock for tests, alternate backend, etc.) — see
/// `lib/app/providers.dart` for where the binding happens.
abstract interface class AiService {
  /// Spawn workers eagerly so the first inference doesn't pay the
  /// model-load latency. Optional — the first call to [analyze] /
  /// [analyzeAll] warms up on demand.
  Future<void> warmup();

  /// Single-photo inference. Throws on failure.
  Future<AnalysisResult> analyze(Photo photo);

  /// Many-photo inference, streamed as results complete (not in input
  /// order). Implementations must enforce bounded concurrency so the
  /// UI never gets buried under a backlog.
  Stream<AnalysisResult> analyzeAll(List<Photo> photos);

  /// Shut down workers and release native resources.
  Future<void> dispose();
}
