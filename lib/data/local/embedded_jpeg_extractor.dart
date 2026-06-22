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
///
/// **Selection priority**: standard DCT-based JPEGs (SOF0 / SOF1 / SOF2,
/// marker bytes 0xC0–0xC2) are always preferred over lossless JPEGs (SOF3,
/// marker 0xC3). Camera DNGs often embed the compressed RAW sensor data as a
/// large lossless JPEG, which Flutter / dart:ui cannot decode. The actual
/// camera preview is always a standard DCT JPEG and is selected here even
/// when a larger lossless JPEG is also present. Among candidates of the same
/// type, the largest one wins (preview vs. tiny thumbnail).
Uint8List? extractLargestEmbeddedJpeg(Uint8List bytes) {
  // Tracks the best candidate in each tier separately.
  // Tier 0: standard DCT (SOF0/1/2) — preferred.
  // Tier 1: lossless (SOF3) or unknown type — fallback.
  var bestStart = -1;
  var bestEnd = -1;
  var bestIsStandard = false; // true when bestStart points at a DCT JPEG

  var i = 0;
  final n = bytes.length;
  while (i + 2 < n) {
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
      final end = _walkJpeg(bytes, i);
      if (end > 0) {
        final isStandard = _isStandardDctJpeg(bytes, i);
        final size = end - i;
        final bestSize = bestEnd - bestStart;

        // Replace current best when:
        // • We found a standard JPEG and the current best is lossless/unknown, OR
        // • Same type and this one is larger.
        if ((isStandard && !bestIsStandard) ||
            (isStandard == bestIsStandard && size > bestSize)) {
          bestStart = i;
          bestEnd = end;
          bestIsStandard = isStandard;
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

/// Returns true when the JPEG at [soi] uses a standard DCT encoding
/// (SOF0 = 0xC0 baseline, SOF1 = 0xC1 extended sequential, SOF2 = 0xC2
/// progressive). Returns false for lossless (SOF3 = 0xC3) or arithmetic
/// variants (0xC9–0xCF), which Flutter / dart:ui cannot render.
bool _isStandardDctJpeg(Uint8List bytes, int soi) {
  var i = soi + 2; // skip SOI
  final n = bytes.length;
  while (i + 1 < n) {
    if (bytes[i] != 0xFF) return false;
    // Skip fill bytes
    while (i + 1 < n && bytes[i + 1] == 0xFF) {
      i++;
    }
    final marker = bytes[i + 1];
    i += 2;
    // SOF markers that indicate DCT-based encoding
    if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) return true;
    // Any other SOF-range marker (0xC3, 0xC5–0xCF) means non-standard
    if ((marker >= 0xC3 && marker <= 0xCF) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      return false;
    }
    // Stop-markers without a length field
    if (marker == 0xD8 || marker == 0xD9 || marker == 0xDA ||
        marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      return false;
    }
    // Length-prefixed segment: skip over it
    if (i + 1 >= n) return false;
    final segLen = (bytes[i] << 8) | bytes[i + 1];
    if (segLen < 2) return false;
    i += segLen;
  }
  return false;
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
