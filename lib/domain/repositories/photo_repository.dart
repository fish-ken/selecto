import '../entities/photo.dart';

/// Owns the photo set on disk. Implementations live in `data/`.
abstract interface class PhotoRepository {
  /// Quick, content-free pass over [rootPath] returning a map of directory
  /// path → scannable file count (checked by extension only — no file reads,
  /// no RAW preview extraction). Used to populate the side-panel folder tree
  /// immediately and to know when each directory has been fully loaded so its
  /// loading indicator can be cleared individually.
  Future<Map<String, int>> discoverDirectories(String rootPath);

  /// Recursively scan [rootPath] and yield photos as they are found.
  /// Streamed so the UI can render the grid incrementally without
  /// blocking on huge directories.
  Stream<Photo> scanDirectory(String rootPath);

  /// One-shot variant for small dirs or tests.
  Future<List<Photo>> listDirectory(String rootPath);

  /// Read raw bytes (used by AI preprocessing inside an isolate).
  Future<List<int>> readBytes(String path);

  /// Move [photo]'s file into [destDir], creating the directory if it
  /// doesn't exist. Returns the new absolute path. Name collisions are
  /// resolved by appending " (n)" before the extension. For RAW files the
  /// sidecar preview cache is left untouched (it's keyed off the original
  /// path and regenerated on demand).
  Future<String> movePhoto(Photo photo, String destDir);
}
