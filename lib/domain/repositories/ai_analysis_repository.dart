import '../entities/analysis_result.dart';
import '../entities/photo.dart';

/// Facade over the AI layer. UI / use cases never see ONNX or isolates.
abstract interface class AiAnalysisRepository {
  /// Run inference on a single photo, using the cache when available.
  Future<AnalysisResult> analyze(Photo photo);

  /// Run inference across many photos. Cached results are yielded first
  /// (immediately, without inference), then uncached results follow as
  /// they complete from the worker pool. Results are not in input order.
  Stream<AnalysisResult> analyzeAll(List<Photo> photos);

  /// Returns cached results for [photos] under the current model,
  /// keyed by [AnalysisResult.photoCacheKey]. Photos without a cached
  /// entry are absent from the map (not an error).
  Future<Map<String, AnalysisResult>> loadCached(List<Photo> photos);
}
