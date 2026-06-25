import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/local/raw_preview_cache.dart';
import '../../domain/entities/photo.dart';
import '../../l10n/l10n.dart';
import '../gallery/gallery_controller.dart';
import '../gallery/gallery_state.dart';
import '../gallery/modifier_keys.dart';
import '../shared/raw_aware_image.dart';
import 'widgets/filmstrip.dart';
import 'widgets/info_panel.dart';
import 'widgets/viewer_shortcuts.dart';

/// Lightroom-style detail / loupe view.
///
///   ┌─────────────────────────────────────────────┐
///   │                                             │
///   │             [ large photo ]                 │  ← BoxFit.contain
///   │                                             │     preserves AR
///   │                                             │
///   ├─────────────────────────────────────────────┤
///   │ [thumb] [thumb] [▣ thumb ▣] [thumb] [thumb] │  ← Filmstrip
///   └─────────────────────────────────────────────┘
///
/// Reads selection state from [galleryControllerProvider] so navigation
/// (←/→, filmstrip tap) stays in sync with the gallery underneath.
class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key});

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  // Index whose neighbors we've already queued for preview precache, so each
  // is scheduled once rather than on every rebuild.
  int? _precachedAround;

  // Info-panel visibility lives in a keepAlive provider so it persists across
  // opening/closing the viewer. Toggled by the top-bar button or the `i` key.
  void _toggleInfo() => ref.read(viewerInfoVisibleProvider.notifier).toggle();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(galleryControllerProvider);
    final ctrl = ref.read(galleryControllerProvider.notifier);
    final t = ref.watch(stringsProvider);
    final infoVisible = ref.watch(viewerInfoVisibleProvider);
    final rawCache = ref.watch(rawPreviewCacheProvider);

    // Warm the preview cache for adjacent photos so stepping ←/→ shows the
    // next photo's soft preview instantly — instead of a black gap or the
    // previous frame — before its full-resolution decode lands.
    _precacheNeighbors(state);

    void close() {
      // Use pop when possible (preserves underlying gallery state).
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }

    final photo = state.currentPhoto;
    if (photo == null) {
      // No photos loaded — there's nothing to show; bounce back.
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: ViewerShortcuts(
        onMove: ctrl.moveCursor,
        onExtendSelection: ctrl.extendSelection,
        onAddSelection: ctrl.addCursorSelection,
        onTogglePick: ctrl.togglePickCurrent,
        onClose: close,
        onToggleInfo: _toggleInfo,
        child: Column(
          children: [
            _TopBar(
              isInBestShots: isInBestShotsPath(photo.path),
              fileName: photo.path.split(RegExp(r'[\\/]')).last,
              onClose: close,
              closeTooltip: t.tr('viewerClose'),
              positionLabel: t.tr('viewerPosition', {
                'index': (state.selectedIndex + 1).toString(),
                'total': state.visiblePhotos.length.toString(),
              }),
              infoVisible: infoVisible,
              infoTooltip: t.tr('info'),
              onToggleInfo: _toggleInfo,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    // No key: keep one _ZoomableImage alive across photo
                    // changes so the Image's `gaplessPlayback` can bridge them
                    // — the previous photo stays on screen until the next
                    // finishes decoding, instead of flashing black on every
                    // navigation. Zoom is reset in didUpdateWidget instead.
                    child: _ZoomableImage(
                      photo: photo,
                      rawCache: rawCache,
                      // Right-click on the main image toggles pick on the
                      // currently displayed photo (no need to leave the viewer).
                      onSecondaryTap: () => ctrl.togglePickByPath(photo.path),
                    ),
                  ),
                  if (infoVisible)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: InfoPanel(
                        // Re-key per photo so the panel reloads its EXIF +
                        // histogram for the newly shown image.
                        key: ValueKey(photo.cacheKey),
                        photo: photo,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 110,
              child: Filmstrip(
                photos: state.visiblePhotos,
                selectedIndex: state.selectedIndex,
                picked: state.picked,
                resultsByCacheKey: state.results,
                onTap: (i) {
                  final mods = ref.read(modifierKeysProvider);
                  if (mods.shift) {
                    ctrl.selectRangeTo(i);
                  } else if (mods.toggleSelect) {
                    ctrl.toggleSelectAt(i);
                  } else {
                    ctrl.selectSingle(i);
                  }
                },
                onMoveToBestShots: (i) =>
                    _relocate(context, ref, state.visiblePhotos[i].path,
                        toBestShots: true),
                onRemoveFromBestShots: (i) =>
                    _relocate(context, ref, state.visiblePhotos[i].path,
                        toBestShots: false),
                moveToBestShotsLabel: t.tr('moveToBestShots'),
                removeFromBestShotsLabel: t.tr('removeFromBestShots'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Decodes the ±neighbors' soft previews ahead of time so the next ←/→
  /// step finds the preview already in the image cache and paints it on the
  /// first frame. Scheduled once per cursor position via [_precachedAround].
  void _precacheNeighbors(GalleryState state) {
    final index = state.selectedIndex;
    if (index == _precachedAround) return;
    _precachedAround = index;
    final width = _previewCacheWidth(context);
    final rawCache = ref.read(rawPreviewCacheProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final offset in const [-3, -2, -1, 1, 2, 3]) {
        final i = index + offset;
        if (i < 0 || i >= state.visiblePhotos.length) continue;
        precacheImage(
          _previewProvider(state.visiblePhotos[i], rawCache, width),
          context,
        );
      }
    });
  }
}

/// Pan/zoom surface for the loupe image.
///
/// - **Double-click** toggles between fit-to-window (1×) and 200%, centered
///   on the cursor. A second double-click anywhere returns to 1×.
/// - **Ctrl + mouse wheel** zooms in/out around the pointer.
/// - When zoomed, drag to pan (handled by [InteractiveViewer]).
///
/// Closing the viewer stays on Esc/Enter (see [ViewerShortcuts]) — the
/// old double-click-to-close gesture is now the zoom toggle.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.photo,
    required this.rawCache,
    required this.onSecondaryTap,
  });

  final Photo photo;
  final RawPreviewCache rawCache;
  final VoidCallback onSecondaryTap;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  // Drives the eased transitions for both double-tap and Ctrl+wheel zoom
  // so scale changes glide instead of snapping. Created in initState (not a
  // `late final` initializer): the lazy initializer would otherwise run on
  // first access, which — if the user never zoomed this photo — happens
  // inside dispose(). Building an AnimationController there calls
  // createTicker → TickerMode.of(context), an ancestor lookup that throws
  // once the element is deactivated.
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  Offset? _lastTapPosition;

  static const double _minScale = 1.0;
  static const double _maxScale = 8.0;
  static const double _doubleTapScale = 4.0;
  static const _doubleTapDuration = Duration(milliseconds: 220);
  static const _wheelDuration = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _doubleTapDuration,
    )..addListener(() {
        final anim = _animation;
        if (anim != null) _controller.value = anim.value;
      });
  }

  @override
  void didUpdateWidget(_ZoomableImage old) {
    super.didUpdateWidget(old);
    // Navigated to a different photo (same widget, since we no longer key by
    // path). Drop any in-flight zoom animation and snap back to fit so each
    // photo opens at 1× — the reset the ValueKey used to give us for free.
    if (old.photo.path != widget.photo.path) {
      _animController.stop();
      _controller.value = Matrix4.identity();
      _lastTapPosition = null;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  /// Eased tween from the current transform to [target]. Restarting mid-flight
  /// is fine — `begin` is read from wherever the matrix currently sits, so
  /// rapid wheel notches chase smoothly instead of jumping.
  void _animateTo(Matrix4 target, Duration duration) {
    _animation = Matrix4Tween(begin: _controller.value, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController
      ..duration = duration
      ..reset()
      ..forward();
  }

  void _handleDoubleTap() {
    final Matrix4 target;
    if (_scale > _minScale + 0.01) {
      // Already zoomed — glide back to fit.
      target = Matrix4.identity();
    } else {
      // Zoom in to 200%, centered on the point the user clicked.
      final focal = _lastTapPosition;
      const z = _doubleTapScale;
      target = focal == null
          ? Matrix4.diagonal3Values(z, z, 1)
          // T(-focal·(z-1)) · S(z): scale up, then shift so the tapped
          // point stays put under the cursor.
          : (Matrix4.translationValues(
              -focal.dx * (z - 1), -focal.dy * (z - 1), 0)
            ..multiply(Matrix4.diagonal3Values(z, z, 1)));
    }
    _animateTo(target, _doubleTapDuration);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Only zoom when Ctrl is held; otherwise let the scroll fall through.
    if (!HardwareKeyboard.instance.isControlPressed) return;

    final factor = event.scrollDelta.dy > 0 ? 0.85 : 1.15;
    final target = (_scale * factor).clamp(_minScale, _maxScale);
    final applied = target / _scale;
    if ((applied - 1.0).abs() < 1e-6) return;

    final focal = event.localPosition;
    // Scale around the pointer: T(focal) · S(applied) · T(-focal) · current.
    final zoom = Matrix4.translationValues(focal.dx, focal.dy, 0)
      ..multiply(Matrix4.diagonal3Values(applied, applied, 1))
      ..multiply(Matrix4.translationValues(-focal.dx, -focal.dy, 0));
    _animateTo(zoom * _controller.value, _wheelDuration);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        onDoubleTapDown: (d) => _lastTapPosition = d.localPosition,
        onDoubleTap: _handleDoubleTap,
        onSecondaryTapDown: (_) => widget.onSecondaryTap(),
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: _minScale,
          maxScale: _maxScale,
          // Keep the image edges within the viewport while panning.
          boundaryMargin: EdgeInsets.zero,
          // Scale is driven manually (double-tap + Ctrl+wheel) so the
          // built-in plain-scroll zoom doesn't fire on a bare mouse wheel.
          // Panning (drag when zoomed) stays enabled.
          scaleEnabled: false,
          // The child fills the whole pane so pointer coordinates map
          // 1:1 onto the transform space used by double-tap / Ctrl+wheel.
          child: SizedBox.expand(
            child: _ProgressivePhoto(
              photo: widget.photo,
              rawCache: widget.rawCache,
            ),
          ),
        ),
      ),
    );
  }
}

/// Decode width for the loupe preview layer. Only one dimension is set so
/// the aspect ratio is preserved (passing both width and height distorts
/// it), snapped to a 128-px bucket so a window resize doesn't change the
/// ResizeImage cache key and force a re-decode every frame.
int _previewCacheWidth(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final raw = MediaQuery.sizeOf(context).width * dpr / 2;
  const bucket = 128;
  return ((raw / bucket).ceil() * bucket).clamp(256, 768).toInt();
}

/// Provider for the preview layer. Shared by [_ProgressivePhoto] and the
/// neighbor precache in [_ViewerScreenState] so both resolve to the same
/// image-cache entry — that's what lets ←/→ paint the next preview at once.
///
/// Backed by [RawAwareImage], so a RAW photo whose preview cache was cleared
/// mid-session is re-extracted on demand instead of failing to decode.
ImageProvider _previewProvider(Photo photo, RawPreviewCache cache, int width) =>
    rawAwarePreview(photo, cache, width: width);

/// Two-layer image for the loupe view that avoids the black pane a single
/// full-resolution `Image.file` shows while it decodes the whole 24MP
/// buffer on first view. It stacks:
///
///   1. a small, fast-decoding **preview** underneath — aspect-preserving,
///      ~a frame to decode, and precached for neighbors — so navigating to
///      a photo shows a soft version of *that* photo immediately;
///   2. the **full-resolution** image on top. It has no `gaplessPlayback`,
///      so the instant the photo changes it clears (revealing the new
///      preview) instead of leaving the previous, now-stale frame in front,
///      then re-appears once decoded — a clean soft → sharp swap.
///
/// Both use `BoxFit.contain`, so the two layers stay pixel-aligned.
class _ProgressivePhoto extends StatelessWidget {
  const _ProgressivePhoto({required this.photo, required this.rawCache});

  final Photo photo;
  final RawPreviewCache rawCache;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Soft, fast preview underneath. NO gaplessPlayback on purpose: with
        // it, the layer holds the last *completed* decode, so flipping faster
        // than previews decode leaves an earlier photo lingering here until it
        // catches up. Without it the layer clears on every photo change and
        // only ever shows this photo (precached neighbors keep normal
        // navigation instant; only flips that outrun the precache blank
        // briefly instead of showing a stale image).
        Image(
          image: _previewProvider(photo, rawCache, _previewCacheWidth(context)),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
          // Stay silent on error — the full-res layer shows the broken icon.
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        // Full-resolution on top. No gaplessPlayback: on a photo change it
        // clears immediately so the previous photo can't sit in front of the
        // new preview; it re-appears once this photo's full decode lands.
        Image(
          image: rawAwarePreview(photo, rawCache),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image,
              size: 64,
              color: Colors.white54,
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isInBestShots,
    required this.fileName,
    required this.onClose,
    required this.closeTooltip,
    required this.positionLabel,
    required this.infoVisible,
    required this.infoTooltip,
    required this.onToggleInfo,
  });

  /// Whether the current photo lives in a `BestShots` folder — shown with
  /// the same teal square check badge as the gallery tile's top-right.
  final bool isInBestShots;
  final String fileName;
  final VoidCallback onClose;
  final String closeTooltip;
  final String positionLabel;
  final bool infoVisible;
  final String infoTooltip;
  final VoidCallback onToggleInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: closeTooltip,
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          if (isInBestShots) ...[
            // Same teal rounded-square check badge as the gallery tile's
            // top-right BestShots marker.
            Container(
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
            const SizedBox(width: 16),
          ],
          Text(
            positionLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: infoTooltip,
            icon: Icon(
              Icons.info_outline,
              color: infoVisible
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white,
            ),
            onPressed: onToggleInfo,
          ),
        ],
      ),
    );
  }
}

/// Moves [path] (or the whole current selection, if [path] is part of it)
/// into / out of the `BestShots` folder and reports the count via SnackBar.
/// Mirrors the gallery grid's right-click relocate so both views behave the
/// same. Errors surface through the controller's state listener.
Future<void> _relocate(
  BuildContext context,
  WidgetRef ref,
  String path, {
  required bool toBestShots,
}) async {
  final ctrl = ref.read(galleryControllerProvider.notifier);
  final picked = ref.read(galleryControllerProvider).picked;
  final targets = picked.contains(path) ? picked.toList() : [path];
  final messenger = ScaffoldMessenger.maybeOf(context);
  final t = ref.read(stringsProvider);

  final moved = toBestShots
      ? await ctrl.moveToBestShots(targets)
      : await ctrl.removeFromBestShots(targets);
  if (moved <= 0) return;

  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        toBestShots
            ? t.tr('movedToBestShots', {'count': moved.toString()})
            : t.tr('movedOutOfBestShots', {'count': moved.toString()}),
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}
