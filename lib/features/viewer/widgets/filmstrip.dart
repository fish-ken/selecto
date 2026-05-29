import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/analysis_result.dart';
import '../../../domain/entities/photo.dart';
import '../../gallery/gallery_controller.dart';

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
  });

  final List<Photo> photos;
  final int selectedIndex;
  final Set<String> picked;
  final Map<String, AnalysisResult> resultsByCacheKey;
  final ValueChanged<int> onTap;

  @override
  State<Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<Filmstrip> {
  static const _itemExtent = 96.0; // tile width + horizontal padding
  final _scrollCtrl = ScrollController();
  bool _skipNextEnsureVisible = false;

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
    final skip = _skipNextEnsureVisible;
    _skipNextEnsureVisible = false;
    if (old.selectedIndex != widget.selectedIndex && !skip) {
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

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollCtrl.hasClients) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return; // horizontal wheels (dx) are handled natively
    final target = (_scrollCtrl.offset + dy).clamp(
      _scrollCtrl.position.minScrollExtent,
      _scrollCtrl.position.maxScrollExtent,
    );
    if (target != _scrollCtrl.offset) _scrollCtrl.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: Container(
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
              isInBestShots: isInBestShotsPath(photo.path),
              analysis: widget.resultsByCacheKey[photo.cacheKey],
              onTap: () {
                _skipNextEnsureVisible = true;
                widget.onTap(i);
              },
            );
          },
        ),
      ),
    );
  }
}

class _FilmstripTile extends StatelessWidget {
  const _FilmstripTile({
    required this.photo,
    required this.isCursor,
    required this.isPicked,
    required this.isInBestShots,
    required this.onTap,
    this.analysis,
  });

  final Photo photo;
  final bool isCursor;
  final bool isPicked;
  final bool isInBestShots;
  final VoidCallback onTap;
  final AnalysisResult? analysis;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheDim = (96 * dpr).round().clamp(64, 256).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            border: Border.all(
              color: isCursor || isPicked
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
                if (isInBestShots)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
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
