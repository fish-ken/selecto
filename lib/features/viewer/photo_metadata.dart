import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';

/// EXIF rows + an RGB histogram for one photo, loaded for the viewer's info
/// panel. Both come from the *decodable* file (a plain JPEG, or a RAW's
/// embedded preview JPEG), which carries the shooting EXIF either way.
class PhotoMetadata {
  const PhotoMetadata({required this.exif, required this.histogram});

  /// Curated, formatted rows. [ExifRow.labelKey] is an i18n key the UI
  /// translates; [ExifRow.value] is already display-ready.
  final List<ExifRow> exif;
  final Histogram histogram;
}

class ExifRow {
  const ExifRow(this.labelKey, this.value);
  final String labelKey;
  final String value;
}

/// 256-bin per-channel histogram. [max] is the largest bin across R/G/B
/// (excluding the clipping extremes) for normalizing the chart height.
class Histogram {
  const Histogram(this.r, this.g, this.b, this.max);
  final List<int> r;
  final List<int> g;
  final List<int> b;
  final int max;

  bool get isEmpty => max <= 0;
}

/// Derives the EXIF rows and the histogram for one photo.
///
/// [imagePath] is the decodable image (a plain JPEG, or a RAW's embedded
/// preview) — used for the histogram, and as the EXIF fallback.
/// [exifPath] is the original file (e.g. the `.ARW`); when given and
/// different, EXIF is read from it first. This matters for RAW: formats like
/// Sony ARW are TIFF-based and carry the full shooting EXIF in their IFDs,
/// while the extracted preview JPEG we decode usually has no EXIF segment.
/// [fileBytes] (original file size) is shown as a row when given.
Future<PhotoMetadata> loadPhotoMetadata(
  String imagePath, {
  String? exifPath,
  int? fileBytes,
}) async {
  final imageBytes = await File(imagePath).readAsBytes();

  Map<String, IfdTag> tags = const {};
  final ep = exifPath ?? imagePath;
  if (ep != imagePath) {
    // Read the whole original (RAW headers can reference EXIF values past the
    // first chunk). One-time cost when the panel opens for this photo.
    final rawBytes = await File(ep).readAsBytes();
    // Pre-process vendor-specific RAW formats that the exif package cannot
    // parse directly:
    //   • CR3 (Canon ISOBMFF): EXIF lives in two separate TIFF boxes —
    //     CMT1 (IFD0: Make/Model/DateTime) and CMT2 (EXIF sub-IFD:
    //     ExposureTime/FNumber/ISO/FocalLength). Neither box contains a link
    //     to the other, so we read them separately and merge the results.
    //   • ORF (Olympus/OM System): TIFF-based but uses the non-standard magic
    //     bytes 'IIRO' (0x49 0x49 0x52 0x4F) instead of 'II*\x00' — patch the
    //     two magic bytes so the exif package treats it as a regular TIFF.
    final blobs = _extractExifBlobs(rawBytes);
    if (blobs.length == 1) {
      tags = await _readExifTags(blobs[0]);
    } else if (blobs.length > 1) {
      // CR3: merge tags from all blobs; earlier blobs win on key conflicts so
      // that IFD0 (CMT1) fields like 'Image Make' take priority.
      final merged = <String, IfdTag>{};
      for (final blob in blobs.reversed) {
        merged.addAll(await _readExifTags(blob));
      }
      tags = merged;
    } else {
      tags = await _readExifTags(rawBytes);
    }
  }
  // Fall back to the decodable image's EXIF when the original yielded no
  // usable shooting EXIF — plain JPEGs (where ep == imagePath), RAW formats
  // the parser can't read (e.g. Fuji RAF → 0 tags), or files whose only tags
  // are non-shooting (e.g. a stripped JPEG mis-named .nef).
  if (!_hasShootingExif(tags)) tags = await _readExifTags(imageBytes);

  final exif = _rowsFromTags(tags, fileBytes: fileBytes);
  final histogram = await _histogram(imageBytes);
  return PhotoMetadata(exif: exif, histogram: histogram);
}

// ---------------------------------------------------------------------------
// EXIF
// ---------------------------------------------------------------------------

/// Extracts parseable EXIF/TIFF blobs from a RAW file byte buffer.
///
/// Returns a list of [Uint8List] blobs that can each be passed directly to
/// [readExifFromBytes].  For most formats the list has exactly one entry (the
/// original or a lightly patched copy).  Canon CR3 is the exception: it
/// returns two blobs — CMT1 (IFD0: Make/Model) followed by CMT2 (EXIF
/// sub-IFD: shooting data) — because the two IFDs live in separate ISOBMFF
/// boxes with no cross-reference between them.
///
/// Returns an empty list when the format is already handled by [readExifFromBytes]
/// without any pre-processing (e.g. standard TIFF, JPEG with APP1).
List<Uint8List> _extractExifBlobs(Uint8List bytes) {
  if (bytes.length < 8) return const [];

  // ---- Canon CR3 (ISOBMFF / MP4-box container) ----
  // CR3 starts with an 'ftyp' box (bytes 4-7 == 'ftyp').  The exif package
  // does not understand ISOBMFF at all.  Canon embeds EXIF in two TIFF boxes:
  //   CMT1 → IFD0 tags: Make (0x010F), Model (0x0110), DateTime (0x0132) …
  //   CMT2 → EXIF sub-IFD tags: ExposureTime, FNumber, ISO, FocalLength …
  // Neither box contains a pointer to the other, so both must be read and
  // merged.  Both are valid standard-TIFF streams (II*\x00 magic).
  // The boxes live in the moov header section, well within the first 64 KB.
  if (bytes[4] == 0x66 && bytes[5] == 0x74 &&
      bytes[6] == 0x79 && bytes[7] == 0x70) {
    final blobs = <Uint8List>[];
    final searchEnd = bytes.length < 65536 ? bytes.length - 8 : 65536;
    for (var i = 0; i < searchEnd; i++) {
      // Scan for 'CMT1' (43 4D 54 31) or 'CMT2' (43 4D 54 32).
      if (bytes[i] == 0x43 && bytes[i + 1] == 0x4D && bytes[i + 2] == 0x54 &&
          (bytes[i + 3] == 0x31 || bytes[i + 3] == 0x32)) {
        if (i < 4) continue;
        final boxStart = i - 4;
        final s0 = bytes[boxStart], s1 = bytes[boxStart + 1],
              s2 = bytes[boxStart + 2], s3 = bytes[boxStart + 3];
        final boxSize = (s0 << 24) | (s1 << 16) | (s2 << 8) | s3;
        if (boxSize < 16 || boxStart + boxSize > bytes.length) continue;
        final dataStart = boxStart + 8;
        final dataLen = boxSize - 8;
        if (dataLen < 8) continue;
        // Validate TIFF magic.
        final m0 = bytes[dataStart], m1 = bytes[dataStart + 1],
              m2 = bytes[dataStart + 2], m3 = bytes[dataStart + 3];
        final isLeTiff = m0 == 0x49 && m1 == 0x49 && m2 == 0x2A && m3 == 0x00;
        final isBeTiff = m0 == 0x4D && m1 == 0x4D && m2 == 0x00 && m3 == 0x2A;
        if (!isLeTiff && !isBeTiff) continue;
        blobs.add(Uint8List.sublistView(bytes, dataStart, dataStart + dataLen));
      }
    }
    return blobs; // empty list → caller falls back to readExifFromBytes(rawBytes)
  }

  // ---- Olympus / OM System ORF ----
  // ORF is TIFF-based but uses the non-standard magic 'IIRO' (49 49 52 4F)
  // instead of the standard 'II*\x00' (49 49 2A 00).  The exif package's
  // _isTiff guard rejects any header that doesn't match 'II*\x00' or
  // 'MM\x00*', so ORF files silently produce 0 tags.  Patching bytes [2:3]
  // to 0x2A 0x00 makes it look like a standard little-endian TIFF without
  // altering any IFD offsets, since those are computed from byte 0 onward.
  if (bytes[0] == 0x49 && bytes[1] == 0x49 &&
      bytes[2] == 0x52 && bytes[3] == 0x4F) {
    final patched = Uint8List.fromList(bytes); // copy — never mutate caller's buffer
    patched[2] = 0x2A;
    patched[3] = 0x00;
    return [patched];
  }

  return const []; // standard format — no pre-processing needed
}

Future<Map<String, IfdTag>> _readExifTags(Uint8List bytes) async {
  try {
    return await readExifFromBytes(bytes);
  } catch (_) {
    return const {};
  }
}

/// Whether [tags] carry actual shooting metadata (vs. just colorspace/size).
/// Used to decide whether to fall back to another EXIF source.
///
/// Checks both 'EXIF ...' (from a proper EXIF sub-IFD) and 'Image ...' (from
/// IFD0 directly, as seen in Canon CR3's CMT2 TIFF blob where shooting tags
/// live in IFD0 without an ExifOffset pointer).
bool _hasShootingExif(Map<String, IfdTag> tags) =>
    tags.containsKey('Image Make') ||
    tags.containsKey('Image Model') ||
    tags.containsKey('EXIF FNumber') ||
    tags.containsKey('Image FNumber') ||
    tags.containsKey('EXIF ExposureTime') ||
    tags.containsKey('Image ExposureTime') ||
    tags.containsKey('EXIF DateTimeOriginal') ||
    tags.containsKey('Image DateTimeOriginal');

List<ExifRow> _rowsFromTags(Map<String, IfdTag> tags, {int? fileBytes}) {
  final rows = <ExifRow>[];
  void add(String key, String? value) {
    final v = value?.trim();
    if (v != null && v.isNotEmpty) rows.add(ExifRow(key, v));
  }

  add('exifCamera', _camera(tags));
  add('exifLens', _printable(tags['EXIF LensModel']) ??
      _printable(tags['MakerNote LensModel']));
  add('exifAperture', _aperture(tags));
  add('exifShutter', _shutter(tags));
  add('exifIso', _iso(tags));
  add('exifFocalLength', _focal(tags));
  add('exifDate', _date(tags));
  add('exifDimensions', _dimensions(tags));
  if (fileBytes != null) add('exifFileSize', _fileSize(fileBytes));

  return rows;
}

String? _printable(IfdTag? tag) {
  final s = tag?.printable.trim();
  if (s == null || s.isEmpty || s == '0') return null;
  return s;
}

String? _camera(Map<String, IfdTag> t) {
  final make = _printable(t['Image Make']);
  final model = _printable(t['Image Model']);
  if (model == null) return make;
  if (make == null) return model;
  // Cameras often repeat the make inside the model ("NIKON" + "NIKON Z 6").
  if (model.toUpperCase().startsWith(make.toUpperCase())) return model;
  return '$make $model';
}

String? _aperture(Map<String, IfdTag> t) {
  // 'EXIF FNumber' — from a proper EXIF sub-IFD (most RAW formats, JPEG).
  // 'Image FNumber' — from IFD0 directly (CR3 CMT2 blob, no ExifOffset tag).
  final v = _num(t['EXIF FNumber']) ?? _num(t['Image FNumber']) ??
      _num(t['EXIF ApertureValue']) ?? _num(t['Image ApertureValue']);
  return v == null ? null : 'f/${_trim(v)}';
}

String? _shutter(Map<String, IfdTag> t) {
  final v = _num(t['EXIF ExposureTime']) ?? _num(t['Image ExposureTime']);
  if (v == null || v <= 0) return null;
  if (v >= 1) return '${_trim(v)}s';
  return '1/${(1 / v).round()}s';
}

String? _iso(Map<String, IfdTag> t) {
  final v = _num(t['EXIF ISOSpeedRatings']) ?? _num(t['Image ISOSpeedRatings']) ??
      _num(t['EXIF PhotographicSensitivity']) ?? _num(t['Image PhotographicSensitivity']);
  return v?.round().toString();
}

String? _focal(Map<String, IfdTag> t) {
  final v = _num(t['EXIF FocalLength']) ?? _num(t['Image FocalLength']);
  if (v == null) return null;
  final mm = '${_trim(v)}mm';
  final eq = _num(t['EXIF FocalLengthIn35mmFilm']) ?? _num(t['Image FocalLengthIn35mmFilm']);
  if (eq != null && eq > 0 && eq.round() != v.round()) {
    return '$mm (≈${eq.round()}mm)';
  }
  return mm;
}

String? _date(Map<String, IfdTag> t) {
  final s = _printable(t['EXIF DateTimeOriginal']) ??
      _printable(t['Image DateTimeOriginal']) ??
      _printable(t['Image DateTime']);
  if (s == null) return null;
  // EXIF stores "YYYY:MM:DD HH:MM:SS"; show the date part with dashes.
  final parts = s.split(' ');
  if (parts.length == 2) return '${parts[0].replaceAll(':', '-')} ${parts[1]}';
  return s;
}

String? _dimensions(Map<String, IfdTag> t) {
  final w = _num(t['EXIF ExifImageWidth']) ?? _num(t['Image ImageWidth']);
  final h = _num(t['EXIF ExifImageLength']) ?? _num(t['Image ImageLength']);
  if (w == null || h == null) return null;
  return '${w.round()} × ${h.round()}';
}

String _fileSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// Parses a numeric EXIF value from its printable form, handling rationals
/// ("9/5"), lists ("[100]"), and plain numbers. Avoids depending on the
/// exif package's internal value types.
double? _num(IfdTag? tag) {
  var s = tag?.printable.trim();
  if (s == null || s.isEmpty) return null;
  s = s.replaceAll('[', '').replaceAll(']', '').trim();
  if (s.contains(',')) s = s.split(',').first.trim();
  if (s.contains('/')) {
    final parts = s.split('/');
    if (parts.length != 2) return null;
    final n = double.tryParse(parts[0].trim());
    final d = double.tryParse(parts[1].trim());
    if (n == null || d == null || d == 0) return null;
    return n / d;
  }
  return double.tryParse(s);
}

/// Formats a double without a trailing ".0" (2.8 → "2.8", 8.0 → "8").
String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

// ---------------------------------------------------------------------------
// Histogram
// ---------------------------------------------------------------------------

/// Decodes [bytes] downsampled (~320 px wide via the engine, fast) and bins
/// the pixels into per-channel histograms.
Future<Histogram> _histogram(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 320);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return _emptyHistogram;
    return _binRgba(data.buffer.asUint8List());
  } catch (_) {
    return _emptyHistogram;
  }
}

Histogram _binRgba(Uint8List px) {
  final r = List<int>.filled(256, 0);
  final g = List<int>.filled(256, 0);
  final b = List<int>.filled(256, 0);
  for (var i = 0; i + 3 < px.length; i += 4) {
    r[px[i]]++;
    g[px[i + 1]]++;
    b[px[i + 2]]++;
  }
  // Normalize against the tallest mid-tone bin so a huge pure-black/white
  // clipping spike at 0/255 doesn't flatten the rest of the curve.
  var max = 1;
  for (var i = 1; i < 255; i++) {
    if (r[i] > max) max = r[i];
    if (g[i] > max) max = g[i];
    if (b[i] > max) max = b[i];
  }
  return Histogram(r, g, b, max);
}

final Histogram _emptyHistogram = Histogram(
  List<int>.filled(256, 0),
  List<int>.filled(256, 0),
  List<int>.filled(256, 0),
  0,
);
