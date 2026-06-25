import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Reads and clears the on-disk RAW preview cache
/// (`<support>/raw_previews/*.jpg`).
///
/// The cache is written by [RawPreviewCache]; this class only needs the
/// directory path — it doesn't need to know about extraction logic.
class PreviewCacheManager {
  Future<Directory?> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'raw_previews'));
    return await dir.exists() ? dir : null;
  }

  /// Total size of all cached preview files in bytes.
  Future<int> sizeInBytes() async {
    final dir = await _dir();
    if (dir == null) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Deletes every file in the preview cache directory.
  Future<void> clear() async {
    final dir = await _dir();
    if (dir == null) return;
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }
}
