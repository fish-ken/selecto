import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/entities/analysis_result.dart';
import '../../../domain/entities/photo.dart';

/// Single grid tile. Uses [Image.file] with `cacheWidth`/`cacheHeight`
/// so the decode produces a thumbnail-sized bitmap instead of a full
/// 24MP buffer — that's the single biggest memory win for huge libraries.
class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.photo,
    required this.thumbExtent,
    required this.isCursor,
    required this.isPicked,
    required this.onTap,
    this.analysis,
  });

  final Photo photo;
  final double thumbExtent;
  final bool isCursor;
  final bool isPicked;
  final VoidCallback onTap;
  final AnalysisResult? analysis;

  @override
  Widget build(BuildContext context) {
    final cacheDim = (thumbExtent * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 1024)
        .toInt();

    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isCursor
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(photo.path),
                  fit: BoxFit.cover,
                  cacheWidth: cacheDim,
                  cacheHeight: cacheDim,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Colors.black26,
                    child: Center(child: Icon(Icons.broken_image, size: 24)),
                  ),
                ),
                if (isPicked) const _PickedBadge(),
                if (analysis != null)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: _ScoreChip(score: analysis!.qualityScore),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickedBadge extends StatelessWidget {
  const _PickedBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 4,
      top: 4,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        score.toStringAsFixed(2),
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}
