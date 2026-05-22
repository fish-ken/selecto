import '../../ai/ai_service.dart';
import '../../domain/entities/analysis_result.dart';
import '../../domain/entities/photo.dart';
import '../../domain/repositories/ai_analysis_repository.dart';
import '../local/app_database.dart';

/// Sits between the domain layer and the AI facade. Its job is to
/// (1) check the Drift cache before invoking inference, (2) persist
/// fresh results, and (3) translate row models ↔ domain entities.
///
/// `modelId` is the file name of the currently selected ONNX model. It's
/// folded into the DB primary key so switching models doesn't reuse stale
/// scores from a different model — and switching back later reuses them
/// instead of re-running inference.
class AiAnalysisRepositoryImpl implements AiAnalysisRepository {
  AiAnalysisRepositoryImpl({
    required AiService service,
    required AppDatabase db,
    required String modelId,
  })  : _service = service,
        _db = db,
        _modelId = modelId;

  final AiService _service;
  final AppDatabase _db;
  final String _modelId;

  String _dbKey(String photoCacheKey) => '$photoCacheKey::$_modelId';

  @override
  Future<AnalysisResult?> getCached(Photo photo) async {
    final row = await _db.findByCacheKey(_dbKey(photo.cacheKey));
    return row == null ? null : _toDomain(row, photo.cacheKey);
  }

  @override
  Future<AnalysisResult> analyze(Photo photo) async {
    final cached = await getCached(photo);
    if (cached != null) return cached;
    final fresh = await _service.analyze(photo);
    await _persist(fresh, photo.path);
    return fresh;
  }

  @override
  Stream<AnalysisResult> analyzeAll(List<Photo> photos) async* {
    final pending = <Photo>[];
    final pathByKey = <String, String>{};
    for (final photo in photos) {
      pathByKey[photo.cacheKey] = photo.path;
      final cached = await getCached(photo);
      if (cached != null) {
        yield cached;
      } else {
        pending.add(photo);
      }
    }
    await for (final result in _service.analyzeAll(pending)) {
      final path = pathByKey[result.photoCacheKey] ?? '';
      await _persist(result, path);
      yield result;
    }
  }

  Future<void> _persist(AnalysisResult r, String path) {
    return _db.upsert(
      CachedAnalysesCompanion.insert(
        cacheKey: _dbKey(r.photoCacheKey),
        path: path,
        qualityScore: r.qualityScore,
        sharpnessScore: r.sharpnessScore,
        faceCount: r.faceCount,
        hasBlink: r.hasBlink,
        computedAt: r.computedAt,
      ),
    );
  }

  AnalysisResult _toDomain(CachedAnalysis row, String photoCacheKey) =>
      AnalysisResult(
        photoCacheKey: photoCacheKey,
        qualityScore: row.qualityScore,
        sharpnessScore: row.sharpnessScore,
        faceCount: row.faceCount,
        hasBlink: row.hasBlink,
        computedAt: row.computedAt,
      );
}
