import '../entities/analysis_result.dart';
import '../entities/photo.dart';
import '../repositories/ai_analysis_repository.dart';

class AnalyzePhotos {
  const AnalyzePhotos(this._repo);
  final AiAnalysisRepository _repo;

  Stream<AnalysisResult> call(List<Photo> photos) => _repo.analyzeAll(photos);
}
