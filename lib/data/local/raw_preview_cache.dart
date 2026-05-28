import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Extracts the embedded JPEG preview from camera RAW files and caches
/// the bytes under the app support directory, so the rest of the
/// pipeline (grid thumbnails, viewer, AI inference) can treat RAW files
/// like any other JPEG.
///
/// Strategy:
///   1. Check the cache — `<support>/raw_previews/<md5(cacheKey)>.jpg`.
///   2. On miss, run `exiftool -b -PreviewImage` (then `-JpgFromRaw`,
///      then `-OtherImage`) until one returns non-empty bytes.
///   3. Write the bytes to the cache file and return its path.
///
/// All the work to debayer the RAW sensor data is intentionally skipped
/// — the embedded preview the camera already created is good enough for
/// culling and ~100× faster than a full RAW decode.
class RawPreviewCache {
  RawPreviewCache({this.maxConcurrent = 4});

  /// Cap on simultaneous `exiftool` invocations. Each spawn is ~30ms of
  /// overhead, so we run several in parallel to amortize the fork cost
  /// without thrashing disk.
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

  // ---- exiftool availability ----
  bool? _hasExiftool;

  Future<bool> get hasExiftool async {
    if (_hasExiftool != null) return _hasExiftool!;
    try {
      final r = await Process.run('exiftool', ['-ver']);
      _hasExiftool = r.exitCode == 0;
      if (_hasExiftool!) {
        _log.info('exiftool detected: ${(r.stdout as String).trim()}');
      } else {
        _log.warning('exiftool returned exit ${r.exitCode}');
      }
    } catch (e) {
      _hasExiftool = false;
      _log.warning(
        'exiftool not found in PATH — RAW files will be skipped. '
        'Install with: winget install -e --id OliverBetz.ExifTool  (Windows)',
      );
    }
    return _hasExiftool!;
  }

  // ---- cache directory (lazy) ----
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
  /// null when extraction failed (exiftool missing, no embedded preview,
  /// corrupt RAW, etc.). Cached across runs.
  ///
  /// [mtime] and [size] are used in the cache key so the cache
  /// invalidates if the user re-shoots / overwrites the RAW.
  Future<String?> extractPreview(
    File rawFile, {
    required DateTime mtime,
    required int size,
  }) async {
    if (!await hasExiftool) return null;

    final dir = await _ensureCacheDir();
    final keyInput = '${rawFile.path}::${mtime.millisecondsSinceEpoch}::$size';
    final hash = md5.convert(utf8.encode(keyInput)).toString();
    final cachePath = p.join(dir.path, '$hash.jpg');
    final cacheFile = File(cachePath);

    if (await cacheFile.exists()) return cachePath;

    await _acquire();
    try {
      // Different vendors store the preview under different tags.
      // PreviewImage covers Sony/Nikon/Canon/etc; JpgFromRaw is Canon;
      // OtherImage shows up on some Fuji bodies.
      for (final tag in const ['-PreviewImage', '-JpgFromRaw', '-OtherImage']) {
        final result = await Process.run(
          'exiftool',
          ['-b', tag, rawFile.path],
          stdoutEncoding: null, // get raw bytes, not decoded text
        );
        if (result.exitCode != 0) continue;
        final bytes = result.stdout as List<int>;
        if (bytes.isEmpty) continue;
        await cacheFile.writeAsBytes(bytes, flush: true);
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
