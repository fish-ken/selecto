import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/entities/analysis_result.dart';
import '../../../domain/entities/photo.dart';

/// Horizontal thumbnail strip shown along the bottom of the viewer.
/// Auto-scrolls to keep the current photo centred.
class Filmstrip extends StatefulWidget {
  const Filmstrip({
    super.key,
    required this.photos,
    required this.selectedIndex,
    required this.picked,
    required this.resultsByCacheKey,
    required this.onTap,
    this.onSecondaryTap,
  });

  final List<Photo> photos;
  final int selectedIndex;
  final Set<String> picked;
  final Map<String, AnalysisResult> resultsByCacheKey;
  final ValueChanged<int> onTap;

  /// Right-click handler — toggles pick on the clicked tile.
  final ValueChanged<int>? onSecondaryTap;

  @override
  State<Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<Filmstrip> {
  static const _itemExtent = 96.0; // tile width + horizontal padding
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureVisible(widget.selectedIndex);
    });
  }

  @override
  void didUpdateWidget(Filmstrip old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _ensureVisible(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _ensureVisible(int index) {
    if (!_scrollCtrl.hasClients) return;
    final viewport = _scrollCtrl.position.viewportDimension;
    final target = (index * _itemExtent) - (viewport / 2) + (_itemExtent / 2);
    final max = _scrollCtrl.position.maxScrollExtent;
    final min = _scrollCtrl.position.minScrollExtent;
    _scrollCtrl.animateTo(
      target.clamp(min, max),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        itemCount: widget.photos.length,
        itemExtent: _itemExtent,
        // Stable items aren't auto-kept-alive — they re-decode on scroll.
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, i) {
          final photo = widget.photos[i];
          return _FilmstripTile(
            photo: photo,
            isCursor: i == widget.selectedIndex,
            isPicked: widget.picked.contains(photo.path),
            analysis: widget.resultsByCacheKey[photo.cacheKey],
            onTap: () => widget.onTap(i),
            onSecondaryTap: widget.onSecondaryTap == null
                ? null
                : () => widget.onSecondaryTap!(i),
          );
        },
      ),
    );
  }
}

class _FilmstripTile extends StatelessWidget {
  const _FilmstripTile({
    required this.photo,
    required this.isCursor,
    required this.isPicked,
    required this.onTap,
    this.onSecondaryTap,
    this.analysis,
  });

  final Photo photo;
  final bool isCursor;
  final bool isPicked;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final AnalysisResult? analysis;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheDim = (96 * dpr).round().clamp(64, 256).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        // onSecondaryTapDown fires the moment the right button presses
        // down (no arena wait — secondary and primary recognizers don't
        // compete with each other since they handle different buttons).
        onSecondaryTapDown:
            onSecondaryTap == null ? null : (_) => onSecondaryTap!(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            border: Border.all(
              color: isCursor
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(photo.decodablePath),
                  fit: BoxFit.cover,
                  cacheWidth: cacheDim,
                  cacheHeight: cacheDim,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Colors.black45,
                    child: Center(
                      child: Icon(Icons.broken_image, size: 16),
                    ),
                  ),
                ),
                if (isPicked)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (analysis != null)
                  Positioned(
                    left: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        analysis!.qualityScore.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
