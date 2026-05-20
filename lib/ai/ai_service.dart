import '../domain/entities/analysis_result.dart';
import '../domain/entities/photo.dart';

/// Public AI surface. The UI / repositories talk to this only.
abstract interface class AiService {
  Future<void> warmup();
  Future<AnalysisResult> analyze(Photo photo);
  Stream<AnalysisResult> analyzeAll(List<Photo> photos);
  Future<void> dispose();
}
