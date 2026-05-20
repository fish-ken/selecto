import 'package:flutter_test/flutter_test.dart';
import 'package:selecto/domain/entities/analysis_result.dart';
import 'package:selecto/domain/entities/photo.dart';
import 'package:selecto/domain/usecases/select_best_shots.dart';

void main() {
  group('SelectBestShots', () {
    final now = DateTime(2026, 1, 1);
    Photo photo(String name) => Photo(
          path: name,
          byteSize: 1,
          modifiedAt: now,
        );

    AnalysisResult result(
      Photo p, {
      required double q,
      required double s,
      bool blink = false,
    }) {
      return AnalysisResult(
        photoCacheKey: p.cacheKey,
        qualityScore: q,
        sharpnessScore: s,
        faceCount: 0,
        hasBlink: blink,
        computedAt: now,
      );
    }

    test('drops blinks and low-sharpness, ranks by quality', () {
      final a = photo('a');
      final b = photo('b');
      final c = photo('c');
      final d = photo('d');

      final selector = const SelectBestShots();
      final out = selector(
        photos: [a, b, c, d],
        resultsByCacheKey: {
          a.cacheKey: result(a, q: 0.9, s: 0.8),
          b.cacheKey: result(b, q: 0.95, s: 0.2), // blurry — dropped
          c.cacheKey: result(c, q: 0.7, s: 0.9),
          d.cacheKey: result(d, q: 0.99, s: 0.9, blink: true), // blink — dropped
        },
        topK: 2,
      );

      expect(out.map((p) => p.path), ['a', 'c']);
    });
  });
}
