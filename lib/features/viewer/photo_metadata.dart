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

/// Reads [path] once and derives both the EXIF rows and the histogram.
/// [fileBytes] (the original file size) is shown as a row when given.
Future<PhotoMetadata> loadPhotoMetadata(String path, {int? fileBytes}) async {
  final bytes = await File(path).readAsBytes();
  final exif = await _readExif(bytes, fileBytes: fileBytes);
  final histogram = await _histogram(bytes);
  return PhotoMetadata(exif: exif, histogram: histogram);
}

// ---------------------------------------------------------------------------
// EXIF
// ---------------------------------------------------------------------------

Future<List<ExifRow>> _readExif(Uint8List bytes, {int? fileBytes}) async {
  Map<String, IfdTag> tags = const {};
  try {
    tags = await readExifFromBytes(bytes);
  } catch (_) {
    tags = const {};
  }

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
  final v = _num(t['EXIF FNumber']) ?? _num(t['EXIF ApertureValue']);
  return v == null ? null : 'f/${_trim(v)}';
}

String? _shutter(Map<String, IfdTag> t) {
  final v = _num(t['EXIF ExposureTime']);
  if (v == null || v <= 0) return null;
  if (v >= 1) return '${_trim(v)}s';
  return '1/${(1 / v).round()}s';
}

String? _iso(Map<String, IfdTag> t) {
  final v = _num(t['EXIF ISOSpeedRatings']) ?? _num(t['EXIF PhotographicSensitivity']);
  return v?.round().toString();
}

String? _focal(Map<String, IfdTag> t) {
  final v = _num(t['EXIF FocalLength']);
  if (v == null) return null;
  final mm = '${_trim(v)}mm';
  final eq = _num(t['EXIF FocalLengthIn35mmFilm']);
  if (eq != null && eq > 0 && eq.round() != v.round()) {
    return '$mm (≈${eq.round()}mm)';
  }
  return mm;
}

String? _date(Map<String, IfdTag> t) {
  final s = _printable(t['EXIF DateTimeOriginal']) ?? _printable(t['Image DateTime']);
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
