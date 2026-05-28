import '../entities/analysis_result.dart';
import '../entities/photo.dart';

/// Facade over the AI layer. UI / use cases never see ONNX or isolates.
abstract interface class AiAnalysisRepository {
  /// Run inference on a single photo.
  Future<AnalysisResult> analyze(Photo photo);

  /// Run inference across many photos. Implementations fan out to a worker
  /// pool and yield results as they complete (not in order).
  Stream<AnalysisResult> analyzeAll(List<Photo> photos);
}
