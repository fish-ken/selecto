import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../gallery/gallery_controller.dart';
import 'widgets/filmstrip.dart';
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
class ViewerScreen extends ConsumerWidget {
  const ViewerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(galleryControllerProvider);
    final ctrl = ref.read(galleryControllerProvider.notifier);

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
        onTogglePick: ctrl.togglePickCurrent,
        onClose: close,
        child: Column(
          children: [
            _TopBar(
              total: state.photos.length,
              index: state.selectedIndex,
              isPicked: state.picked.contains(photo.path),
              fileName: photo.path.split(RegExp(r'[\\/]')).last,
              onClose: close,
            ),
            Expanded(
              child: GestureDetector(
                onDoubleTap: close, // double-click anywhere to leave
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Image.file(
                    File(photo.decodablePath),
                    // Preserve original aspect ratio; let Flutter scale
                    // to fit the available pane.
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 110,
              child: Filmstrip(
                photos: state.photos,
                selectedIndex: state.selectedIndex,
                picked: state.picked,
                resultsByCacheKey: state.results,
                onTap: ctrl.setCursor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.total,
    required this.index,
    required this.isPicked,
    required this.fileName,
    required this.onClose,
  });

  final int total;
  final int index;
  final bool isPicked;
  final String fileName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close (Esc)',
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
          if (isPicked) ...[
            const Icon(Icons.check_circle, color: Colors.tealAccent, size: 18),
            const SizedBox(width: 6),
            const Text('Picked',
                style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
            const SizedBox(width: 16),
          ],
          Text(
            '${index + 1} / $total',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
