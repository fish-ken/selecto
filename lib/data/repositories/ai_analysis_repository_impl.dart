import '../../ai/ai_service.dart';
import '../../domain/entities/analysis_result.dart';
import '../../domain/entities/photo.dart';
import '../../domain/repositories/ai_analysis_repository.dart';
import '../local/app_database.dart';

/// Sits between the domain layer and the AI facade. Its job is to
/// (1) check the Drift cache before invoking inference, (2) persist
/// fresh results, and (3) translate row models ↔ domain entities.
class AiAnalysisRepositoryImpl implements AiAnalysisRepository {
  AiAnalysisRepositoryImpl({
    required AiService service,
    required AppDatabase db,
  })  : _service = service,
        _db = db;

  final AiService _service;
  final AppDatabase _db;

  @override
  Future<AnalysisResult?> getCached(Photo photo) async {
    final row = await _db.findByCacheKey(photo.cacheKey);
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<AnalysisResult> analyze(Photo photo) async {
    final cached = await getCached(photo);
    if (cached != null) return cached;
    final fresh = await _service.analyze(photo);
    await _persist(fresh);
    return fresh;
  }

  @override
  Stream<AnalysisResult> analyzeAll(List<Photo> photos) async* {
    final pending = <Photo>[];
    for (final photo in photos) {
      final cached = await getCached(photo);
      if (cached != null) {
        yield cached;
      } else {
        pending.add(photo);
      }
    }
    await for (final result in _service.analyzeAll(pending)) {
      await _persist(result);
      yield result;
    }
  }

  Future<void> _persist(AnalysisResult r) {
    return _db.upsert(
      CachedAnalysesCompanion.insert(
        cacheKey: r.photoCacheKey,
        path: '',
        qualityScore: r.qualityScore,
        sharpnessScore: r.sharpnessScore,
        faceCount: r.faceCount,
        hasBlink: r.hasBlink,
        computedAt: r.computedAt,
      ),
    );
  }

  AnalysisResult _toDomain(CachedAnalysis row) => AnalysisResult(
        photoCacheKey: row.cacheKey,
        qualityScore: row.qualityScore,
        sharpnessScore: row.sharpnessScore,
        faceCount: row.faceCount,
        hasBlink: row.hasBlink,
        computedAt: row.computedAt,
      );
}
