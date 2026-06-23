import 'package:drift/drift.dart' show Value;

import '../../ai/ai_service.dart';
import '../../domain/entities/analysis_result.dart';
import '../../domain/entities/photo.dart';
import '../../domain/repositories/ai_analysis_repository.dart';
import '../local/app_database.dart';

/// Wraps the AI facade with a Drift-backed cache keyed by
/// (Photo.cacheKey, modelId).
///
/// On [analyzeAll]:
///   1. Cached rows are yielded immediately — no inference, no waiting.
///   2. Uncached photos are dispatched to the worker pool; each result is
///      persisted before being yielded.
///
/// The cache is per-model: switching models shows fresh inference results
/// for that model, or restores previously computed scores if available.
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

  @override
  Future<AnalysisResult> analyze(Photo photo) async {
    final cached =
        await _db.findByCacheKeyAndModel(photo.cacheKey, _modelId);
    if (cached != null) return _fromRow(cached);

    final result = await _service.analyze(photo);
    await _persist(photo, result);
    return result;
  }

  @override
  Stream<AnalysisResult> analyzeAll(List<Photo> photos) async* {
    if (photos.isEmpty) return;

    final cacheKeys = photos.map((p) => p.cacheKey).toList();
    final rows = await _db.findAllByModel(cacheKeys, _modelId);
    final cachedKeys = <String>{};

    for (final row in rows) {
      cachedKeys.add(row.cacheKey);
      yield _fromRow(row);
    }

    final uncached =
        photos.where((p) => !cachedKeys.contains(p.cacheKey)).toList();
    if (uncached.isEmpty) return;

    final photoByKey = {for (final p in uncached) p.cacheKey: p};
    await for (final result in _service.analyzeAll(uncached)) {
      final photo = photoByKey[result.photoCacheKey];
      if (photo != null) await _persist(photo, result);
      yield result;
    }
  }

  @override
  Future<Map<String, AnalysisResult>> loadCached(List<Photo> photos) async {
    if (photos.isEmpty) return const {};
    final cacheKeys = photos.map((p) => p.cacheKey).toList();
    final rows = await _db.findAllByModel(cacheKeys, _modelId);
    return {for (final row in rows) row.cacheKey: _fromRow(row)};
  }

  AnalysisResult _fromRow(CachedAnalysis row) => AnalysisResult(
        photoCacheKey: row.cacheKey,
        qualityScore: row.qualityScore,
        sharpnessScore: row.sharpnessScore,
        faceCount: row.faceCount,
        hasBlink: row.hasBlink,
        computedAt: row.computedAt,
      );

  Future<void> _persist(Photo photo, AnalysisResult result) =>
      _db.upsert(CachedAnalysesCompanion(
        cacheKey: Value(result.photoCacheKey),
        modelId: Value(_modelId),
        path: Value(photo.path),
        qualityScore: Value(result.qualityScore),
        sharpnessScore: Value(result.sharpnessScore),
        faceCount: Value(result.faceCount),
        hasBlink: Value(result.hasBlink),
        computedAt: Value(result.computedAt),
      ));
}
