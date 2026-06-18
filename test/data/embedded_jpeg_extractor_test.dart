import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:selecto/data/local/embedded_jpeg_extractor.dart';
import 'package:selecto/data/local/raw_preview_cache.dart';

/// Builds a structurally valid JPEG: SOI, APP0, DQT, SOF0, SOS,
/// [entropyBytes] of entropy data (including a stuffed FF 00 and a restart
/// marker to exercise those paths), EOI. Optionally embeds [app1Payload]
/// as an APP1 segment (how EXIF carries a nested thumbnail JPEG).
Uint8List buildJpeg({int entropyBytes = 64, List<int>? app1Payload}) {
  final b = BytesBuilder();
  b.add([0xFF, 0xD8]); // SOI
  if (app1Payload != null) {
    final len = app1Payload.length + 2;
    b.add([0xFF, 0xE1, len >> 8, len & 0xFF]);
    b.add(app1Payload);
  }
  b.add([0xFF, 0xE0, 0x00, 0x10]); // APP0, length 16
  b.add(List.filled(14, 0x4A));
  b.add([0xFF, 0xDB, 0x00, 0x43]); // DQT, length 67
  b.add(List.filled(0x41, 0x01));
  // SOF0: 8-bit, 16×16, 1 component
  b.add([0xFF, 0xC0, 0x00, 0x0B, 8, 0, 16, 0, 16, 1, 1, 0x11, 0]);
  // SOS: 1 component
  b.add([0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 0, 0x3F, 0]);
  b.add(List.filled(entropyBytes, 0xA5));
  b.add([0xFF, 0x00, 0xFF, 0xD0, 0x12, 0x34]); // stuffing + RST0 + data
  b.add([0xFF, 0xD9]); // EOI
  return b.toBytes();
}

Uint8List junk(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 37 + 11) & 0xFF));

void main() {
  group('extractLargestEmbeddedJpeg', () {
    test('returns null for bytes with no JPEG', () {
      expect(extractLargestEmbeddedJpeg(junk(4096)), isNull);
    });

    test('extracts a JPEG surrounded by junk, byte-exact', () {
      final jpeg = buildJpeg();
      final raw = Uint8List.fromList([...junk(512), ...jpeg, ...junk(512)]);
      expect(extractLargestEmbeddedJpeg(raw), equals(jpeg));
    });

    test('picks the largest of several embedded JPEGs', () {
      final thumb = buildJpeg(entropyBytes: 32);
      final preview = buildJpeg(entropyBytes: 5000);
      final raw = Uint8List.fromList(
        [...junk(100), ...thumb, ...junk(100), ...preview, ...junk(100)],
      );
      expect(extractLargestEmbeddedJpeg(raw), equals(preview));
    });

    test('a nested thumbnail inside APP1 does not truncate the outer JPEG',
        () {
      final nested = buildJpeg(entropyBytes: 16);
      final outer = buildJpeg(entropyBytes: 2000, app1Payload: nested);
      final raw = Uint8List.fromList([...junk(64), ...outer, ...junk(64)]);
      expect(extractLargestEmbeddedJpeg(raw), equals(outer));
    });

    test('returns null for a truncated JPEG (no EOI)', () {
      final jpeg = buildJpeg();
      final truncated = Uint8List.sublistView(jpeg, 0, jpeg.length - 2);
      final raw = Uint8List.fromList([...junk(64), ...truncated]);
      expect(extractLargestEmbeddedJpeg(raw), isNull);
    });

    test('rejects a bare SOI+EOI pair with no scan data', () {
      final raw = Uint8List.fromList(
        [...junk(64), 0xFF, 0xD8, 0xFF, 0xD9, ...junk(64)],
      );
      expect(extractLargestEmbeddedJpeg(raw), isNull);
    });
  });

  group('RawPreviewCache', () {
    test('extracts and caches a preview from a fake RAW', () async {
      final tmp = await Directory.systemTemp.createTemp('selecto_raw_test');
      addTearDown(() => tmp.delete(recursive: true));

      final jpeg = buildJpeg(entropyBytes: 3000);
      final rawFile = File('${tmp.path}${Platform.pathSeparator}shot.nef');
      await rawFile
          .writeAsBytes([...junk(1024), ...jpeg, ...junk(1024)], flush: true);
      final stat = await rawFile.stat();

      final cacheDir = await Directory('${tmp.path}'
              '${Platform.pathSeparator}cache')
          .create();
      final cache = RawPreviewCache(cacheDir: cacheDir);

      final previewPath = await cache.extractPreview(
        rawFile,
        mtime: stat.modified,
        size: stat.size,
      );

      expect(previewPath, isNotNull);
      expect(await File(previewPath!).readAsBytes(), equals(jpeg));

      // Second call must hit the cache and return the same path.
      expect(
        await cache.extractPreview(rawFile,
            mtime: stat.modified, size: stat.size),
        equals(previewPath),
      );
    });
  });
}
