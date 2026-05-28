import '../entities/analysis_result.dart';
import '../entities/photo.dart';

/// Pure domain logic: given photos + their analysis, pick the keepers.
///
/// Strategy: drop anything below [minSharpness] or with blinks, then
/// keep the top-K by [AnalysisResult.qualityScore].
///
/// Scores are on the 0..10 scale (see [AnalysisResult] docs).
class SelectBestShots {
  const SelectBestShots();

  List<Photo> call({
    required List<Photo> photos,
    required Map<String, AnalysisResult> resultsByCacheKey,
    double minSharpness = 4.0,
    int? topK,
  }) {
    final scored = <(Photo, AnalysisResult)>[];
    for (final p in photos) {
      final r = resultsByCacheKey[p.cacheKey];
      if (r == null) continue;
      scored.add((p, r));
    }
    scored.sort((a, b) => b.$2.qualityScore.compareTo(a.$2.qualityScore));
    final limited = topK == null ? scored : scored.take(topK);
    return limited.map((e) => e.$1).toList(growable: false);
  }
}
