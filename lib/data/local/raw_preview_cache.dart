import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'embedded_jpeg_extractor.dart';

/// Extracts the embedded JPEG preview from camera RAW files and caches
/// the bytes under the app support directory, so the rest of the
/// pipeline (grid thumbnails, viewer, AI inference) can treat RAW files
/// like any other JPEG.
///
/// Strategy:
///   1. Check the cache — `<support>/raw_previews/<md5(cacheKey)>.jpg`.
///   2. On miss, scan the RAW for its largest embedded JPEG — pure Dart,
///      zero external dependencies (see embedded_jpeg_extractor.dart).
///   3. Write the bytes to the cache file and return its path.
///
/// All the work to debayer the RAW sensor data is intentionally skipped
/// — the embedded preview the camera already created is good enough for
/// culling and ~100× faster than a full RAW decode.
class RawPreviewCache {
  RawPreviewCache({this.maxConcurrent = 4, Directory? cacheDir})
      : _cacheDir = cacheDir;

  /// Cap on simultaneous extractions. Each one reads the whole RAW into a
  /// worker isolate, so this bounds transient memory (~maxConcurrent ×
  /// file size) and keeps the disk from thrashing.
  final int maxConcurrent;

  static final _log = Logger('RawPreviewCache');

  /// Extensions we treat as RAW. Extend as needed for less-common bodies.
  static const _rawExts = <String>{
    '.nef', // Nikon
    '.cr2', '.cr3', // Canon
    '.arw', // Sony
    '.raf', // Fuji
    '.orf', // Olympus
    '.rw2', // Panasonic
    '.dng', // generic / Pentax / DJI / phones
    '.pef', // Pentax
    '.srw', // Samsung
    '.x3f', // Sigma
    '.3fr', // Hasselblad
    '.iiq', '.fff', // Phase One / Imacon
  };

  static bool isRaw(String path) =>
      _rawExts.contains(p.extension(path).toLowerCase());

  // ---- bounded-concurrency semaphore ----
  int _inFlight = 0;
  final _waiters = <Completer<void>>[];

  Future<void> _acquire() {
    if (_inFlight < maxConcurrent) {
      _inFlight++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future.then((_) => _inFlight++);
  }

  void _release() {
    _inFlight--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  // ---- cache directory (lazy; injectable for tests) ----
  Directory? _cacheDir;

  Future<Directory> _ensureCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'raw_previews'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Returns the path of a JPEG that visually represents [rawFile], or
  /// null when extraction failed (no embedded preview, corrupt RAW,
  /// etc.). Cached across runs.
  ///
  /// [mtime] and [size] are used in the cache key so the cache
  /// invalidates if the user re-shoots / overwrites the RAW.
  Future<String?> extractPreview(
    File rawFile, {
    required DateTime mtime,
    required int size,
  }) async {
    final dir = await _ensureCacheDir();
    // v2: bumped when extraction logic changed (SOF0 preferred over SOF3
    // lossless). Old v1 cache entries contain lossless JPEGs that Flutter
    // cannot decode; the version prefix makes them orphans without deleting
    // them proactively.
    const cacheVersion = 'v2';
    final keyInput = '$cacheVersion::${rawFile.path}::${mtime.millisecondsSinceEpoch}::$size';
    final hash = md5.convert(utf8.encode(keyInput)).toString();
    final cachePath = p.join(dir.path, '$hash.jpg');
    final cacheFile = File(cachePath);

    if (await cacheFile.exists()) return cachePath;

    await _acquire();
    try {
      // Runs in a throwaway isolate — the scan reads the whole file and
      // would otherwise stall the UI isolate.
      final rawPath = rawFile.path;
      if (await Isolate.run(
        () => extractEmbeddedJpegToFile(rawPath, cachePath),
      )) {
        return cachePath;
      }
      _log.warning('no embedded preview found in ${rawFile.path}');
      return null;
    } catch (e, st) {
      _log.warning('RAW preview extract failed for ${rawFile.path}', e, st);
      return null;
    } finally {
      _release();
    }
  }
}
