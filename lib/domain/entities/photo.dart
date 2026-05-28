/// A single photo on disk. Pure value object — no I/O, no Flutter deps.
/// Equality is by [path]; [pickedAt] / analysis are mutable metadata
/// kept off the entity (held by repositories / state instead).
class Photo {
  const Photo({
    required this.path,
    required this.byteSize,
    required this.modifiedAt,
    this.width,
    this.height,
    this.previewPath,
  });

  /// Original file path. For RAW files this is the .NEF / .CR2 / etc.
  /// Stable identity used by `state.picked` and the analysis cache key,
  /// even when the file isn't directly decodable by Flutter.
  final String path;

  final int byteSize;
  final DateTime modifiedAt;
  final int? width;
  final int? height;

  /// For RAW files, the path of a cached JPEG preview that Flutter's
  /// image codecs (and our AI preprocessing) can actually decode. Null
  /// for normal JPEG/PNG/etc.
  final String? previewPath;

  /// File the image decoder should read. Identical to [path] for plain
  /// JPEG/PNG/etc; points to the cached preview for RAW files.
  String get decodablePath => previewPath ?? path;

  bool get isRaw => previewPath != null;

  /// Cache key invariant across runs: same content => same key.
  /// (path, mtime, size) is a cheap proxy for content identity.
  /// Uses the *original* path so a RAW keeps the same key regardless of
  /// whether its preview cache file exists.
  String get cacheKey =>
      '$path::${modifiedAt.millisecondsSinceEpoch}::$byteSize';

  @override
  bool operator ==(Object other) => other is Photo && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
