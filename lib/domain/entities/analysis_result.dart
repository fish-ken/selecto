/// AI analysis output for a single photo.
///
/// Scores are on a **0..10 scale** (NIMA's natural MOS range). A score of
/// exactly 0 is the "not analyzed / decode failure" sentinel — real
/// inference output can't reach it because MOS is in [1, 10].
class AnalysisResult {
  const AnalysisResult({
    required this.photoCacheKey,
    required this.qualityScore,
    required this.sharpnessScore,
    required this.faceCount,
    required this.hasBlink,
    required this.computedAt,
  });

  /// Maps to [Photo.cacheKey] — survives renames if path is stable.
  final String photoCacheKey;

  /// Composite "best shot" score, 0..10. Higher is better.
  final double qualityScore;

  /// 0 (blurry) → 10 (tack sharp). Drives the blur filter.
  final double sharpnessScore;

  final int faceCount;

  /// True if at least one face has closed eyes.asdf
  final bool hasBlink;

  final DateTime computedAt;
}
