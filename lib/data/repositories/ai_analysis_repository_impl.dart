import '../../ai/ai_service.dart';
import '../../domain/entities/analysis_result.dart';
import '../../domain/entities/photo.dart';
import '../../domain/repositories/ai_analysis_repository.dart';

/// Thin passthrough to the AI facade. Caching is intentionally disabled —
/// every request re-runs inference so results always reflect the current
/// model and image state (no stale DB hits when model weights change).
class AiAnalysisRepositoryImpl implements AiAnalysisRepository {
  AiAnalysisRepositoryImpl({required AiService service}) : _service = service;

  final AiService _service;

  @override
  Future<AnalysisResult> analyze(Photo photo) => _service.analyze(photo);

  @override
  Stream<AnalysisResult> analyzeAll(List<Photo> photos) =>
      _service.analyzeAll(photos);
}
