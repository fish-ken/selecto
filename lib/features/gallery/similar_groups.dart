import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../../domain/entities/photo.dart';

/// A cluster of visually-similar photos, named `group-0`, `group-1`, …
class PhotoGroup {
  const PhotoGroup({required this.name, required this.photoPaths});

  /// Stable display/identity name (`group-<index>`).
  final String name;

  /// Paths of the photos in this group, in their original scan order.
  final List<String> photoPaths;

  int get count => photoPaths.length;
}

/// Result of a similarity pass: the groups plus a path→group-name index so
/// the gallery can filter by a chosen group in O(1).
class SimilarGroups {
  const SimilarGroups({required this.groups, required this.groupOf});

  final List<PhotoGroup> groups;

  /// Maps a photo path to the name of the group it belongs to (only photos
  /// that landed in a multi-photo group are present).
  final Map<String, String> groupOf;

  static const empty = SimilarGroups(groups: [], groupOf: {});
}

/// Computes a 64-bit difference hash (dHash) for [path] and groups photos
/// whose hashes are within [threshold] Hamming distance. Runs off the UI
/// isolate (call via `Isolate.run`): decoding even small thumbnails for
/// thousands of photos must not block the main thread.
///
/// Only groups of 2+ photos are returned, ordered by the position of their
/// earliest member so `group-0` is the first burst encountered top-to-bottom.
Future<SimilarGroups> computeSimilarGroups(
  List<Photo> photos, {
  int threshold = 10,
}) async {
  if (photos.length < 2) return SimilarGroups.empty;

  // 1) Hash every photo (skip ones that fail to decode).
  final hashes = <int, int>{}; // photo index -> dHash bits
  for (var i = 0; i < photos.length; i++) {
    final h = await _dHash(photos[i].decodablePath);
    if (h != null) hashes[i] = h;
  }

  // 2) Union-find: link photos within Hamming threshold. O(n²) on the hash
  // (fast: integer popcount), which is fine for typical culling sets.
  final indices = hashes.keys.toList();
  final parent = {for (final i in indices) i: i};
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]!]!;
      x = parent[x]!;
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (var a = 0; a < indices.length; a++) {
    for (var b = a + 1; b < indices.length; b++) {
      final ia = indices[a], ib = indices[b];
      if (_hamming(hashes[ia]!, hashes[ib]!) <= threshold) union(ia, ib);
    }
  }

  // 3) Bucket by root, preserving scan order within each bucket.
  final buckets = <int, List<int>>{};
  for (final i in indices) {
    buckets.putIfAbsent(find(i), () => []).add(i);
  }

  // 4) Keep multi-photo groups; order by earliest member; name sequentially.
  final multi = buckets.values.where((m) => m.length >= 2).toList()
    ..sort((a, b) => a.first.compareTo(b.first));

  final groups = <PhotoGroup>[];
  final groupOf = <String, String>{};
  for (var g = 0; g < multi.length; g++) {
    final name = 'group-$g';
    final paths = [for (final i in multi[g]) photos[i].path];
    groups.add(PhotoGroup(name: name, photoPaths: paths));
    for (final path in paths) {
      groupOf[path] = name;
    }
  }
  return SimilarGroups(groups: groups, groupOf: groupOf);
}

/// dHash: downscale to 9×8 grayscale, then bit[i] = (pixel left > pixel right).
/// Returns 64 bits packed into an int, or null if the image can't be decoded.
Future<int?> _dHash(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    // 9 wide so 8 horizontal comparisons per row; engine downscale is cheap.
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 9,
      targetHeight: 8,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return null;
    final px = data.buffer.asUint8List();

    int gray(int x, int y) {
      final o = (y * 9 + x) * 4;
      // Rec. 601 luma, integer-weighted.
      return (px[o] * 77 + px[o + 1] * 150 + px[o + 2] * 29) >> 8;
    }

    var bits = 0;
    var bit = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (gray(x, y) > gray(x + 1, y)) bits |= 1 << bit;
        bit++;
      }
    }
    return bits;
  } catch (_) {
    return null;
  }
}

int _hamming(int a, int b) {
  var x = a ^ b;
  var count = 0;
  while (x != 0) {
    count += x & 1;
    x >>= 1;
  }
  return count;
}

/// True if [path] is a candidate for similarity hashing — same set the
/// gallery scanner accepts. (Kept here so the worker has no scanner dep.)
bool isHashablePhoto(String path) {
  const exts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.tif', '.tiff'};
  return exts.contains(p.extension(path).toLowerCase());
}
