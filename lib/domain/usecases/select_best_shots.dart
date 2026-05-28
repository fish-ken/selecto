import '../entities/analysis_result.dart';
import '../entities/photo.dart';

/// Pure domain logic: given photos + their analysis, pick the keepers.
///
/// Strategy: compute the score threshold at the `(1 - topPercentile)`
/// quantile of all analyzed photos' [AnalysisResult.qualityScore], then
/// return every photo whose score is >= that threshold.
///
/// Ties at the boundary are kept — the resulting set can be slightly
/// larger than `topPercentile × N`, which is preferable to picking an
/// arbitrary tie-break.
class SelectBestShots {
  const SelectBestShots();

  List<Photo> call({
    required List<Photo> photos,
    required Map<String, AnalysisResult> resultsByCacheKey,
    double topPercentile = 0.2,
  }) {
    final scored = <(Photo, AnalysisResult)>[];
    for (final p in photos) {
      final r = resultsByCacheKey[p.cacheKey];
      if (r == null) continue;
      scored.add((p, r));
    }
    if (scored.isEmpty) return const [];

    final scoresAsc = scored
        .map((e) => e.$2.qualityScore)
        .toList(growable: false)
      ..sort();
    final cutoffIndex = (scoresAsc.length * (1.0 - topPercentile))
        .floor()
        .clamp(0, scoresAsc.length - 1);
    final threshold = scoresAsc[cutoffIndex];

    return scored
        .where((e) => e.$2.qualityScore >= threshold)
        .map((e) => e.$1)
        .toList(growable: false);
  }
}
