import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/raw_preview_cache.dart';
import '../../domain/entities/photo.dart';

/// [ImageProvider] for a [Photo] that survives the RAW preview cache being
/// cleared while the app is running.
///
/// Plain JPEG/PNG photos decode straight from [Photo.path]. RAW photos decode
/// from their cached embedded-JPEG preview ([Photo.previewPath]); if that cache
/// file is missing — e.g. the user cleared the preview cache from Settings
/// mid-session — it is re-extracted on demand, the moment the image is needed,
/// *before* decoding. So a cleared cache transparently rebuilds itself the next
/// time each photo is painted instead of leaving a broken-image icon.
///
/// Because re-extraction happens inside the decode, no cache invalidation or
/// provider plumbing is needed: an entry only re-decodes from disk on a cold
/// load or after eviction, and that is exactly when the file is re-created.
///
/// Identity is [Photo.cacheKey] (plus [scale]), so this composes with
/// [ResizeImage] for the grid/filmstrip thumbnails exactly like [FileImage]
/// did, and shares one in-memory image-cache entry across the grid, filmstrip,
/// and viewer.
@immutable
class RawAwareImage extends ImageProvider<RawAwareImage> {
  const RawAwareImage(this.photo, this._cache, {this.scale = 1.0});

  final Photo photo;
  final double scale;

  /// Shared, long-lived extractor — the same instance the directory scan uses
  /// (see `rawPreviewCacheProvider`), so on-demand re-extraction obeys the same
  /// bounded-concurrency cap. Excluded from equality: it is a process-wide
  /// singleton and is not part of the image's identity.
  final RawPreviewCache _cache;

  @override
  Future<RawAwareImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<RawAwareImage>(this);

  @override
  ImageStreamCompleter loadImage(
    RawAwareImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: photo.decodablePath,
    );
  }

  Future<ui.Codec> _loadAsync(
    RawAwareImage key,
    ImageDecoderCallback decode,
  ) async {
    final path = await _ensurePath();
    final bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) {
      // Evict so a later paint retries (and can re-extract) instead of caching
      // the failure forever.
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('$path is empty and cannot be loaded as an image.');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  Future<String> _ensurePath() => ensureDecodable(photo, _cache);

  @override
  bool operator ==(Object other) =>
      other is RawAwareImage &&
      other.photo.cacheKey == photo.cacheKey &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(photo.cacheKey, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'RawAwareImage')}("${photo.decodablePath}", '
      'scale: $scale)';
}

/// Resolves the file to decode for [photo], re-extracting a missing RAW
/// preview first.
///
/// Returns [Photo.path] for plain, directly decodable images. For a RAW whose
/// cached preview is gone (e.g. the cache was cleared mid-session), it
/// re-extracts the embedded JPEG — [RawPreviewCache.extractPreview] is a no-op
/// cache hit when the file is already present, so the common path costs one
/// `exists()` stat — and returns the cache path. On extraction failure it
/// returns the still-missing preview path so the caller surfaces a load error
/// rather than silently handing back the undecodable RAW.
Future<String> ensureDecodable(Photo photo, RawPreviewCache cache) async {
  final preview = photo.previewPath;
  if (preview == null) return photo.path;
  if (await File(preview).exists()) return preview;
  final regenerated = await cache.extractPreview(
    File(photo.path),
    mtime: photo.modifiedAt,
    size: photo.byteSize,
  );
  return regenerated ?? preview;
}

/// Builds the [ImageProvider] for [photo], optionally resized for a thumbnail
/// or preview layer. Resizing matches `Image.file(..., cacheWidth/cacheHeight)`
/// (`allowUpscaling: false`) so callers keep the same decode-resolution memory
/// win they had before. Used by both the viewer's soft-preview layer and its
/// neighbor precache, so the two resolve to the same image-cache entry.
ImageProvider rawAwarePreview(
  Photo photo,
  RawPreviewCache cache, {
  int? width,
  int? height,
}) {
  final ImageProvider base = RawAwareImage(photo, cache);
  if (width == null && height == null) return base;
  return ResizeImage(base, width: width, height: height, allowUpscaling: false);
}

/// Drop-in replacement for the `Image.file(File(photo.decodablePath), …)` calls
/// in the grid and filmstrip. Reads the shared preview cache from Riverpod so
/// the caller doesn't have to thread it through, and re-extracts a cleared RAW
/// preview on demand via [RawAwareImage].
class PhotoImage extends ConsumerWidget {
  const PhotoImage({
    super.key,
    required this.photo,
    this.cacheWidth,
    this.cacheHeight,
    this.fit,
    this.filterQuality = FilterQuality.low,
    this.gaplessPlayback = false,
    this.errorBuilder,
  });

  final Photo photo;
  final int? cacheWidth;
  final int? cacheHeight;
  final BoxFit? fit;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(rawPreviewCacheProvider);
    return Image(
      image: rawAwarePreview(photo, cache,
          width: cacheWidth, height: cacheHeight),
      fit: fit,
      filterQuality: filterQuality,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder,
    );
  }
}
