/// AI analysis output for a single photo. Scores are normalized 0.0..1.0.
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

  /// Composite "best shot" score. Higher is better.
  final double qualityScore;

  /// 0.0 (blurry) → 1.0 (tack sharp). Drives the blur filter.
  final double sharpnessScore;

  final int faceCount;

  /// True if at least one face has closed eyes.
  final bool hasBlink;

  final DateTime computedAt;
}
