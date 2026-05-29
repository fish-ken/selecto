import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n.dart';
import '../settings/settings_dialog.dart';
import 'gallery_controller.dart';
import 'gallery_state.dart';
import 'modifier_keys.dart';
import 'widgets/gallery_shortcuts.dart';
import 'widgets/model_picker.dart';
import 'widgets/photo_tile.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen>
    with WindowListener {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Track modifier keys ourselves (see [ModifierKeysNotifier]) and reset
    // them whenever the window loses focus, so a key-up swallowed by Alt+Tab
    // / the Windows key / a native dialog can't leave Ctrl "stuck" and turn
    // ordinary clicks into multi-selection.
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    windowManager.removeListener(this);
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) =>
      ref.read(modifierKeysProvider.notifier).handle(event);

  @override
  void onWindowBlur() => ref.read(modifierKeysProvider.notifier).reset();

  Future<void> _pickDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    await ref.read(galleryControllerProvider.notifier).openDirectory(path);
  }

  @override
  Widget build(BuildContext context) {
    // Surface errors raised by the gallery controller. Uses `ref.listen`,
    // not `ref.watch` — runs callback on change, doesn't rebuild.
    ref.listen<GalleryState>(galleryControllerProvider, (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final stack = next.errorStack;
        final t = ref.read(stringsProvider);
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            duration: const Duration(seconds: 8),
            content: Row(
              children: [
                Expanded(
                  child: Text(
                    t.tr('errorPrefix', {'message': err.toString()}),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                _SnackTextButton(
                  label: t.tr('copyLog'),
                  onPressed: () => _copyErrorLog(
                    context: context,
                    messenger: messenger,
                    error: err,
                    stack: stack,
                    confirmation: t.tr('logCopied'),
                  ),
                ),
                _SnackTextButton(
                  label: t.tr('dismiss'),
                  onPressed: messenger.hideCurrentSnackBar,
                ),
              ],
            ),
          ),
        );
      }
    });

    return Scaffold(
      appBar: const _GalleryAppBar(),
      body: _GalleryBody(scrollCtrl: _scrollCtrl, onPickDirectory: _pickDirectory),
      bottomNavigationBar: const _StatusBar(),
    );
  }
}

/// AppBar isolated as its own ConsumerWidget so it only rebuilds when
/// the specific fields it shows actually change.
class _GalleryAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _GalleryAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow the watch to a record of just the fields we render.
    final s = ref.watch(galleryControllerProvider.select((s) => (
          rootPath: s.rootPath,
          hasPhotos: s.photos.isNotEmpty,
          analyzing: s.analyzing,
          hasResults: s.results.isNotEmpty,
        )));
    final ctrl = ref.read(galleryControllerProvider.notifier);
    final t = ref.watch(stringsProvider);

    return AppBar(
      title: Text(s.rootPath ?? t.tr('appTitle')),
      actions: [
        const ModelPicker(),
        const SizedBox(width: 8),
        Builder(
          builder: (context) => IconButton(
            tooltip: t.tr('openFolder'),
            onPressed: () async {
              final path = await FilePicker.platform.getDirectoryPath();
              if (path == null) return;
              await ref
                  .read(galleryControllerProvider.notifier)
                  .openDirectory(path);
            },
            icon: const Icon(Icons.folder_open),
          ),
        ),
        IconButton(
          tooltip: t.tr('analyze'),
          onPressed: !s.hasPhotos || s.analyzing ? null : ctrl.analyzeAll,
          icon: s.analyzing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
        ),
        IconButton(
          tooltip: t.tr('selectBest'),
          onPressed: !s.hasResults ? null : ctrl.selectBest,
          icon: const Icon(Icons.star),
        ),
        Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.settings),
            tooltip: t.tr('settings'),
            onPressed: () => SettingsDialog.show(context),
          ),
        ),
      ],
    );
  }
}

/// Body — empty state vs. grid. Watches only what the body decision needs.
class _GalleryBody extends ConsumerWidget {
  const _GalleryBody({required this.scrollCtrl, required this.onPickDirectory});

  final ScrollController scrollCtrl;
  final VoidCallback onPickDirectory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhotos = ref.watch(
      galleryControllerProvider.select((s) => s.photos.isNotEmpty),
    );

    if (!hasPhotos) {
      final scanning = ref.watch(
        galleryControllerProvider.select((s) => s.scanning),
      );
      return _EmptyState(scanning: scanning, onPick: onPickDirectory);
    }

    return _PhotoGrid(scrollCtrl: scrollCtrl);
  }
}

/// The actual grid. Watches `photos.length` for itemCount and ignores
/// everything else — per-tile data flows through fine-grained selectors
/// in the tile's own Consumer.
class _PhotoGrid extends ConsumerWidget {
  const _PhotoGrid({required this.scrollCtrl});

  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosLength = ref.watch(
      galleryControllerProvider.select((s) => s.photos.length),
    );
    final ctrl = ref.read(galleryControllerProvider.notifier);

    final width = MediaQuery.sizeOf(context).width - 32;
    final crossAxisCount = (width / 200).floor().clamp(2, 12).toInt();
    final tileExtent = width / crossAxisCount;

    return GalleryShortcuts(
      crossAxisCount: crossAxisCount,
      onMove: ctrl.moveCursor,
      onTogglePick: ctrl.togglePickCurrent,
      onPickAll: ctrl.pickAll,
      onUnpickAll: ctrl.unpickAll,
      onOpenViewer: () => context.push('/viewer'),
      child: GridView.builder(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1,
        ),
        itemCount: photosLength,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, i) {
          // Tile is its own Consumer — it watches only its own slice of
          // state (this photo's cursor/picked/analysis bits). State
          // changes that don't affect this index produce no rebuild.
          return _PhotoTileConnected(index: i, thumbExtent: tileExtent);
        },
      ),
    );
  }
}

/// Per-tile connector — subscribes only to the slices that actually
/// affect this single tile's visuals. The big win during analysis:
/// when `state.results` gets one new entry, only the tile whose
/// `photo.cacheKey` matches rebuilds. The other 49 visible tiles see
/// their selectors return identical values → no rebuild.
class _PhotoTileConnected extends ConsumerWidget {
  const _PhotoTileConnected({
    required this.index,
    required this.thumbExtent,
  });

  final int index;
  final double thumbExtent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(
      galleryControllerProvider.select(
        (s) => index < s.photos.length ? s.photos[index] : null,
      ),
    );
    if (photo == null) return const SizedBox.shrink();

    final isCursor = ref.watch(
      galleryControllerProvider.select((s) => s.selectedIndex == index),
    );
    final isPicked = ref.watch(
      galleryControllerProvider.select((s) => s.picked.contains(photo.path)),
    );
    final analysis = ref.watch(
      galleryControllerProvider.select((s) => s.results[photo.cacheKey]),
    );
    final ctrl = ref.read(galleryControllerProvider.notifier);
    final t = ref.watch(stringsProvider);

    return PhotoTile(
      photo: photo,
      thumbExtent: thumbExtent,
      isCursor: isCursor,
      isPicked: isPicked,
      analysis: analysis,
      moveToBestShotsLabel: t.tr('moveToBestShots'),
      removeFromBestShotsLabel: t.tr('removeFromBestShots'),
      onTap: () {
        final mods = ref.read(modifierKeysProvider);
        if (mods.shift) {
          ctrl.selectRangeTo(index);
        } else if (mods.toggleSelect) {
          ctrl.toggleSelectAt(index);
        } else {
          ctrl.selectSingle(index);
        }
      },
      onDoubleTap: () {
        ctrl.setCursor(index);
        context.push('/viewer');
      },
      // Right-click opens a context menu to move this photo (or the whole
      // current selection, if this photo is part of it) into / out of the
      // folder's BestShots subfolder.
      isInBestShots: isInBestShotsPath(photo.path),
      onMoveToBestShots: () =>
          _relocate(context, ref, photo.path, toBestShots: true),
      onRemoveFromBestShots: () =>
          _relocate(context, ref, photo.path, toBestShots: false),
    );
  }

  /// Resolves the action target (the whole selection when [path] is part of
  /// it, otherwise just this photo), relocates via the controller, and
  /// reports the count moved. Errors surface through the controller's state
  /// listener in [_GalleryScreenState.build].
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
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.scanning, required this.onPick});
  final bool scanning;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (scanning) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = ref.watch(stringsProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 64),
          const SizedBox(height: 16),
          Text(t.tr('noFolderOpen')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open),
            label: Text(t.tr('chooseFolder')),
          ),
        ],
      ),
    );
  }
}

/// Status bar isolated as its own ConsumerWidget. Counts update frequently
/// during analysis, but the bar is small and self-contained, so its
/// rebuild cost is negligible compared to the grid.
class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(galleryControllerProvider.select((s) => (
          scanning: s.scanning,
          analyzing: s.analyzing,
          total: s.photos.length,
          picked: s.picked.length,
          analyzed: s.results.length,
        )));
    final t = ref.watch(stringsProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (s.scanning)
            Text('${t.tr('scanning')} ')
          else
            Text('${t.tr('photosCount', {'count': s.total.toString()})}  '),
          Text('${t.tr('selectedCount', {'count': s.picked.toString()})}  '),
          if (s.analyzed > 0)
            Text('${t.tr('analyzedCount', {'count': s.analyzed.toString()})}  '),
          if (s.analyzing) Text(t.tr('inferring')),
        ],
      ),
    );
  }
}

/// White, underlined text button used inside the error SnackBar's content
/// row. SnackBarAction can't carry styled labels, so we render TextButtons
/// inline and share their styling through this small helper.
class _SnackTextButton extends StatelessWidget {
  const _SnackTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      // Draw the underline as a container bottom-border instead of
      // TextDecoration.underline. With mixed-script labels (e.g. Korean
      // "로그 복사"), the glyphs come from a fallback font whose underline
      // metrics differ from the Latin font, so the decoration breaks/steps
      // around the space. A border draws one clean continuous line.
      child: Container(
        padding: const EdgeInsets.only(bottom: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white, width: 1.2)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Builds a paste-able log report and writes it to the system clipboard,
/// then shows a brief confirmation SnackBar so the user knows it worked.
Future<void> _copyErrorLog({
  required BuildContext context,
  required ScaffoldMessengerState? messenger,
  required Object error,
  required StackTrace? stack,
  required String confirmation,
}) async {
  final buffer = StringBuffer()
    ..writeln('# Selecto — Error log')
    ..writeln('Timestamp: ${DateTime.now().toIso8601String()}')
    ..writeln()
    ..writeln('## Error')
    ..writeln(error.toString());
  if (stack != null) {
    buffer
      ..writeln()
      ..writeln('## Stack')
      ..writeln(stack.toString());
  }

  await Clipboard.setData(ClipboardData(text: buffer.toString()));

  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(confirmation),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      ),
    );
}
