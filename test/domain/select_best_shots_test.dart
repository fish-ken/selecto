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

      // Scores on the 0..10 scale. Default minSharpness = 4.0.
      final selector = const SelectBestShots();
      final out = selector(
        photos: [a, b, c, d],
        resultsByCacheKey: {
          a.cacheKey: result(a, q: 9.0, s: 8.0),
          b.cacheKey: result(b, q: 9.5, s: 2.0), // blurry — dropped
          c.cacheKey: result(c, q: 7.0, s: 9.0),
          d.cacheKey: result(d, q: 9.9, s: 9.0, blink: true), // blink — dropped
        },
        topK: 2,
      );

      expect(out.map((p) => p.path), ['a', 'c']);
    });
  });
}
