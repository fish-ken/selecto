import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/analysis_result.dart';
import '../../../domain/entities/photo.dart';
import '../../gallery/gallery_state.dart';

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
    required this.onMoveToBestShots,
    required this.onRemoveFromBestShots,
    required this.moveToBestShotsLabel,
    required this.removeFromBestShotsLabel,
  });

  final List<Photo> photos;
  final int selectedIndex;
  final Set<String> picked;
  final Map<String, AnalysisResult> resultsByCacheKey;
  final ValueChanged<int> onTap;

  /// Right-click context-menu actions (by photo index), matching the
  /// gallery tile's BestShots move/remove behavior.
  final ValueChanged<int> onMoveToBestShots;
  final ValueChanged<int> onRemoveFromBestShots;
  final String moveToBestShotsLabel;
  final String removeFromBestShotsLabel;

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
        // Transparent — sits inside a GlassSurface that provides the fill.
        color: Colors.transparent,
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
              onMoveToBestShots: () => widget.onMoveToBestShots(i),
              onRemoveFromBestShots: () => widget.onRemoveFromBestShots(i),
              moveToBestShotsLabel: widget.moveToBestShotsLabel,
              removeFromBestShotsLabel: widget.removeFromBestShotsLabel,
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
    required this.onMoveToBestShots,
    required this.onRemoveFromBestShots,
    required this.moveToBestShotsLabel,
    required this.removeFromBestShotsLabel,
    this.analysis,
  });

  final Photo photo;
  final bool isCursor;
  final bool isPicked;
  final bool isInBestShots;
  final VoidCallback onTap;
  final VoidCallback onMoveToBestShots;
  final VoidCallback onRemoveFromBestShots;
  final String moveToBestShotsLabel;
  final String removeFromBestShotsLabel;
  final AnalysisResult? analysis;

  /// Right-click context menu — identical to the gallery tile's: move the
  /// photo (or the whole current selection) into / out of BestShots.
  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_FilmstripMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _FilmstripMenuAction.moveToBestShots,
          enabled: !isInBestShots,
          child: Text(moveToBestShotsLabel),
        ),
        PopupMenuItem(
          value: _FilmstripMenuAction.removeFromBestShots,
          enabled: isInBestShots,
          child: Text(removeFromBestShotsLabel),
        ),
      ],
    );
    switch (action) {
      case _FilmstripMenuAction.moveToBestShots:
        onMoveToBestShots();
      case _FilmstripMenuAction.removeFromBestShots:
        onRemoveFromBestShots();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheDim = (96 * dpr).round().clamp(64, 256).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            border: Border.all(
              // Selected → solid accent border; cursor-only (the currently
              // viewed photo, or one just Ctrl+click-deselected) → a faint
              // accent border so it reads as focused-but-not-selected.
              color: isPicked
                  ? Theme.of(context).colorScheme.primary
                  : isCursor
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35)
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

enum _FilmstripMenuAction { moveToBestShots, removeFromBestShots }
