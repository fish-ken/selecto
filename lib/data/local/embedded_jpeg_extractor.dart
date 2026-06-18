import 'dart:io';
import 'dart:typed_data';

/// Pure-Dart extraction of the embedded JPEG preview that virtually every
/// camera RAW (NEF / CR2 / CR3 / ARW / RAF / DNG / …) carries for the
/// camera's own LCD playback.
///
/// Rather than parsing each vendor's container format (TIFF IFDs, ISO BMFF
/// boxes, RAF headers, …) we scan the raw bytes for well-formed JPEG
/// streams and return the largest one — RAWs embed a tiny thumbnail *and*
/// a large preview, and "largest" reliably selects the preview. A candidate
/// only counts if its segment structure walks cleanly from SOI through at
/// least one SOS to EOI, which random sensor data essentially never
/// satisfies, so false positives are not a practical concern.

/// Returns the largest well-formed JPEG stream inside [bytes], or null
/// when none is found. The result is a view into [bytes], not a copy.
Uint8List? extractLargestEmbeddedJpeg(Uint8List bytes) {
  var bestStart = -1;
  var bestEnd = -1;
  var i = 0;
  final n = bytes.length;
  while (i + 2 < n) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
      final end = _walkJpeg(bytes, i);
      if (end > 0) {
        if (end - i > bestEnd - bestStart) {
          bestStart = i;
          bestEnd = end;
        }
        // A nested thumbnail (e.g. inside the preview's own EXIF) was
        // already skipped by the walk, so resume after the whole stream.
        i = end;
        continue;
      }
    }
    i++;
  }
  if (bestStart < 0) return null;
  return Uint8List.sublistView(bytes, bestStart, bestEnd);
}

/// Reads [rawPath], extracts the largest embedded JPEG, and writes it to
/// [outPath]. Returns true on success. Top-level and self-contained so it
/// can run via `Isolate.run` — scanning tens of MB must not block the UI
/// isolate.
Future<bool> extractEmbeddedJpegToFile(String rawPath, String outPath) async {
  final bytes = await File(rawPath).readAsBytes();
  final jpeg = extractLargestEmbeddedJpeg(bytes);
  if (jpeg == null) return false;
  await File(outPath).writeAsBytes(jpeg, flush: true);
  return true;
}

/// Walks the JPEG segment structure starting at [soi] (which must point at
/// `FF D8`). Returns the index just past the matching EOI, or -1 when the
/// structure is invalid or truncated.
int _walkJpeg(Uint8List bytes, int soi) {
  final n = bytes.length;
  var i = soi + 2;
  var sawSos = false;
  while (true) {
    if (i + 1 >= n || bytes[i] != 0xFF) return -1;
    // Skip fill bytes (FF FF … before a marker is legal padding).
    while (bytes[i + 1] == 0xFF) {
      i++;
      if (i + 1 >= n) return -1;
    }
    final marker = bytes[i + 1];
    i += 2;
    if (marker == 0xD9) return sawSos ? i : -1; // EOI
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      continue; // TEM / RSTn — standalone markers, no length field
    }
    if (marker == 0xD8 || marker == 0x00) return -1; // corrupt stream
    // Every other marker is followed by a big-endian segment length that
    // includes the length field itself. Nested JPEGs (EXIF thumbnails)
    // live inside an APPn segment and are skipped wholesale here.
    if (i + 1 >= n) return -1;
    final segLen = (bytes[i] << 8) | bytes[i + 1];
    if (segLen < 2) return -1;
    i += segLen;
    if (i > n) return -1;
    if (marker == 0xDA) {
      sawSos = true;
      // Entropy-coded data follows SOS: scan to the next true marker,
      // treating FF 00 (byte stuffing) and FF D0–D7 (restart markers) as
      // data. A literal FF D9 here is the real EOI by construction.
      while (true) {
        if (i + 1 >= n) return -1;
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final m = bytes[i + 1];
        if (m == 0x00 || (m >= 0xD0 && m <= 0xD7)) {
          i += 2;
          continue;
        }
        if (m == 0xFF) {
          i++;
          continue;
        }
        break; // real marker — outer loop re-parses it at [i]
      }
    }
  }
}
