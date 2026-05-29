import 'dart:io';

import 'package:flutter/gestures.dart';
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
    required this.onDoubleTap,
    required this.moveToBestShotsLabel,
    required this.removeFromBestShotsLabel,
    this.onMoveToBestShots,
    this.onRemoveFromBestShots,
    this.isInBestShots = false,
    this.analysis,
  });

  final Photo photo;
  final double thumbExtent;
  final bool isCursor;
  final bool isPicked;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  /// Localized context-menu labels, injected by the connector.
  final String moveToBestShotsLabel;
  final String removeFromBestShotsLabel;

  /// Right-click context-menu actions. Move = relocate into the folder's
  /// `BestShots/` subfolder; Remove = move back out to the parent folder.
  final VoidCallback? onMoveToBestShots;
  final VoidCallback? onRemoveFromBestShots;

  /// Whether this photo currently lives inside a `BestShots` folder —
  /// decides which menu item is enabled.
  final bool isInBestShots;
  final AnalysisResult? analysis;

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_TileMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _TileMenuAction.moveToBestShots,
          enabled: !isInBestShots && onMoveToBestShots != null,
          child: Text(moveToBestShotsLabel),
        ),
        PopupMenuItem(
          value: _TileMenuAction.removeFromBestShots,
          enabled: isInBestShots && onRemoveFromBestShots != null,
          child: Text(removeFromBestShotsLabel),
        ),
      ],
    );
    switch (action) {
      case _TileMenuAction.moveToBestShots:
        onMoveToBestShots?.call();
      case _TileMenuAction.removeFromBestShots:
        onRemoveFromBestShots?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cacheDim = (thumbExtent * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, 1024)
        .toInt();

    return Padding(
      padding: const EdgeInsets.all(4),
      // Use a raw Listener instead of GestureDetector so the click bypasses
      // Flutter's gesture arena entirely. With GestureDetector(onTapDown +
      // onDoubleTap), the TapGestureRecognizer waits ~100 ms (kPressTimeout)
      // before firing because the DoubleTapGestureRecognizer is competing
      // for the same pointer — which is why keyboard navigation felt
      // instant but mouse clicks felt mushy. Listener delivers the
      // PointerDownEvent the moment it arrives.
      child: _InstantClick(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: (pos) => _showContextMenu(context, pos),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isCursor || isPicked
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
                  File(photo.decodablePath),
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
                if (isInBestShots) const _BestShotsBadge(),
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

/// Pointer-down click detector that fires `onTap` the instant a primary
/// button (mouse) or touch contact lands, with no gesture-arena delay,
/// and `onDoubleTap` when a second click arrives within ~280 ms.
///
/// Why not `GestureDetector`? Because pairing `onTapDown` with
/// `onDoubleTap` puts the TapGestureRecognizer in arena contention with
/// the DoubleTapGestureRecognizer. `onTapDown` can't fire until the arena
/// resolves, which costs up to `kPressTimeout` (100 ms) per click — a
/// noticeable lag, especially next to keyboard input which doesn't go
/// through the arena at all.
class _InstantClick extends StatefulWidget {
  const _InstantClick({
    required this.onTap,
    required this.onDoubleTap,
    required this.child,
    this.onSecondaryTapDown,
  });

  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition)? onSecondaryTapDown;
  final Widget child;

  @override
  State<_InstantClick> createState() => _InstantClickState();
}

class _InstantClickState extends State<_InstantClick> {
  // 280 ms is comfortably under the default OS double-click window
  // (typically 400-500 ms on Windows) but above natural single-click
  // jitter. Tweak if needed.
  static const _doubleClickWindowMs = 280;

  int _lastDownMs = 0;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      // Right-click → fire onSecondaryTap immediately, no double-click
      // bookkeeping (doesn't share state with primary clicks).
      if ((event.buttons & kSecondaryButton) != 0) {
        widget.onSecondaryTapDown?.call(event.position);
        return;
      }
      // Non-primary mouse buttons (middle, back, forward) are ignored.
      if ((event.buttons & kPrimaryButton) == 0) return;
    }
    // Primary mouse click or touch — apply the manual double-click test.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDownMs < _doubleClickWindowMs) {
      _lastDownMs = 0;
      widget.onDoubleTap();
    } else {
      _lastDownMs = now;
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      child: widget.child,
    );
  }
}

/// Top-right badge indicating the photo lives in a `BestShots` folder
/// (kept/best). Teal rounded-square badge distinguishes it from the selection accent.
class _BestShotsBadge extends StatelessWidget {
  const _BestShotsBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 4,
      top: 4,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.teal,
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
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
        score.toStringAsFixed(1),
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

enum _TileMenuAction { moveToBestShots, removeFromBestShots }
