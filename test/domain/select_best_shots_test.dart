import 'package:flutter_test/flutter_test.dart';
import 'package:selecto/domain/entities/analysis_result.dart';
import 'package:selecto/domain/entities/photo.dart';
import 'package:selecto/domain/usecases/select_best_shots.dart';

void main() {
  group('SelectBestShots — top-percentile threshold', () {
    final now = DateTime(2026, 1, 1);
    Photo photo(String name) => Photo(
          path: name,
          byteSize: 1,
          modifiedAt: now,
        );

    AnalysisResult result(Photo p, {required double q}) => AnalysisResult(
          photoCacheKey: p.cacheKey,
          qualityScore: q,
          sharpnessScore: 0,
          faceCount: 0,
          hasBlink: false,
          computedAt: now,
        );

    const selector = SelectBestShots();

    test('default top 20% picks the top fifth by qualityScore', () {
      // 10 photos with scores 0.0 .. 9.0.
      final photos = List.generate(10, (i) => photo('p$i'));
      final results = {
        for (var i = 0; i < 10; i++)
          photos[i].cacheKey: result(photos[i], q: i.toDouble()),
      };
      // Sorted asc: [0,1,..,9]. cutoffIndex = floor(10 * 0.8) = 8.
      // Threshold = 8.0 → selects p8 (8.0) and p9 (9.0).
      final out = selector(photos: photos, resultsByCacheKey: results);
      expect(out.map((p) => p.path).toSet(), {'p8', 'p9'});
    });

    test('configurable percentile — top 50% picks the upper half', () {
      final photos = List.generate(10, (i) => photo('p$i'));
      final results = {
        for (var i = 0; i < 10; i++)
          photos[i].cacheKey: result(photos[i], q: i.toDouble()),
      };
      // cutoffIndex = floor(10 * 0.5) = 5. Threshold = 5.0 → 5 photos.
      final out = selector(
        photos: photos,
        resultsByCacheKey: results,
        topPercentile: 0.5,
      );
      expect(out.length, 5);
      expect(out.map((p) => p.path).toSet(), {'p5', 'p6', 'p7', 'p8', 'p9'});
    });

    test('ties at the threshold are all kept', () {
      final a = photo('a');
      final b = photo('b');
      final c = photo('c');
      final d = photo('d');
      final e = photo('e');
      final out = selector(
        photos: [a, b, c, d, e],
        resultsByCacheKey: {
          a.cacheKey: result(a, q: 9.0),
          b.cacheKey: result(b, q: 9.0),
          c.cacheKey: result(c, q: 9.0),
          d.cacheKey: result(d, q: 3.0),
          e.cacheKey: result(e, q: 1.0),
        },
      );
      // sorted asc: [1, 3, 9, 9, 9]. cutoffIndex = floor(5 * 0.8) = 4.
      // Threshold = 9.0 → a, b, c all kept (ties at boundary).
      expect(out.map((p) => p.path).toSet(), {'a', 'b', 'c'});
    });

    test('photos without analysis are excluded', () {
      final a = photo('a');
      final b = photo('b');
      final c = photo('c');
      final out = selector(
        photos: [a, b, c],
        resultsByCacheKey: {
          a.cacheKey: result(a, q: 5.0),
          c.cacheKey: result(c, q: 9.0),
        },
      );
      // Only a, c are scored. sorted asc: [5, 9]. cutoffIndex = floor(2*0.8)=1.
      // Threshold = 9.0 → only c.
      expect(out.map((p) => p.path).toList(), ['c']);
    });

    test('empty input returns empty', () {
      expect(
        selector(photos: const [], resultsByCacheKey: const {}),
        isEmpty,
      );
    });
  });
}
