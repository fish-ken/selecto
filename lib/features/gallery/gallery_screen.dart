import 'package:file_selector/file_selector.dart';
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
    final path = await getDirectoryPath();
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
      title: _FolderTitleButton(
        label: s.rootPath ?? t.tr('appTitle'),
        tooltip: t.tr('changeFolder'),
        onTap: () async {
          final path = await getDirectoryPath();
          if (path == null) return;
          await ref
              .read(galleryControllerProvider.notifier)
              .openDirectory(path);
        },
      ),
      actions: [
        const ModelPicker(),
        const SizedBox(width: 8),
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
class _GalleryBody extends ConsumerStatefulWidget {
  const _GalleryBody({required this.scrollCtrl, required this.onPickDirectory});

  final ScrollController scrollCtrl;
  final VoidCallback onPickDirectory;

  @override
  ConsumerState<_GalleryBody> createState() => _GalleryBodyState();
}

class _GalleryBodyState extends ConsumerState<_GalleryBody> {
  static const double _minPanelWidth = 120.0;
  static const double _maxPanelWidth = 400.0;
  static const double _defaultPanelWidth = 220.0;

  double _panelWidth = _defaultPanelWidth;

  @override
  Widget build(BuildContext context) {
    // Show the main layout (panel + grid) as soon as we know which directories
    // exist — even before photos have been extracted. This lets the folder tree
    // appear immediately while RAW previews are still being generated.
    final showLayout = ref.watch(
      galleryControllerProvider.select(
        (s) => s.photos.isNotEmpty || s.loadingDirs.isNotEmpty,
      ),
    );

    if (!showLayout) {
      final scanning = ref.watch(
        galleryControllerProvider.select((s) => s.scanning),
      );
      return _EmptyState(scanning: scanning, onPick: widget.onPickDirectory);
    }

    // Whether the subfolder panel will actually be visible (mirrors the
    // logic in _SubfolderPanel so we can hide the drag handle too).
    final subfolders =
        ref.watch(galleryControllerProvider.select((s) => s.subfolders));
    // Show the panel (and drag handle) as soon as there are 2+ directory
    // entries — including loading ones — so the tree is visible from the
    // moment discovery finishes.
    final panelVisible = subfolders.length > 1;

    // Left: subfolder navigator (hides itself when there's nothing to
    // navigate). Right: the grid of the currently-visible photos.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubfolderPanel(width: _panelWidth),
        // Drag handle — only shown when the panel itself is visible.
        if (panelVisible)
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _panelWidth = (_panelWidth + details.delta.dx)
                      .clamp(_minPanelWidth, _maxPanelWidth);
                });
              },
              child: Container(
                width: 6,
                color: Colors.transparent,
              ),
            ),
          ),
        Expanded(child: _PhotoGrid(scrollCtrl: widget.scrollCtrl)),
      ],
    );
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
      galleryControllerProvider.select((s) => s.visiblePhotos.length),
    );
    final ctrl = ref.read(galleryControllerProvider.notifier);

    // Size the grid from the actual content width — the side panel takes a
    // slice of the window, so MediaQuery's full width would over-count.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 16; // GridView's 8-px padding × 2
        final crossAxisCount = (width / 200).floor().clamp(2, 12).toInt();
        final tileExtent = width / crossAxisCount;

        return GalleryShortcuts(
          crossAxisCount: crossAxisCount,
          onMove: ctrl.moveCursor,
          onExtendSelection: ctrl.extendSelection,
          onAddSelection: ctrl.addCursorSelection,
          onTogglePick: ctrl.togglePickCurrent,
          onPickAll: ctrl.pickAll,
          onUnpickAll: ctrl.unpickAll,
          onOpenViewer: () {
            // Keyboard-opening the viewer right after a folder switch: make
            // sure a real photo is focused first (the cursor may be parked
            // at -1 to keep the grid from showing a pre-selected tile).
            ctrl.ensureCursor();
            context.push('/viewer');
          },
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
      },
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
        (s) => index < s.visiblePhotos.length ? s.visiblePhotos[index] : null,
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
      // Right-clicking a tile that isn't already selected clears the previous
      // selection and selects only it (so the context-menu action targets the
      // right-clicked photo, not a stale multi-selection). Right-clicking a
      // selected tile keeps the whole selection.
      onContextOpen: () {
        if (!isPicked) ctrl.selectSingle(index);
      },
      // Right-click opens a context menu to move this photo (or the whole
      // current selection, if this photo is part of it) into / out of the
      // folder's A-cut subfolder.
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

/// Clickable AppBar title showing the current root folder. Tapping it opens
/// the folder picker so the user can switch to a different folder.
class _FolderTitleButton extends StatelessWidget {
  const _FolderTitleButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Left-hand navigator listing the directories that contain photos. Picking
/// one filters the grid/viewer to just that directory (a view-only filter —
/// the top-left folder label and BestShots moves are unaffected). Hides
/// itself when there's only a single directory to show.
///
/// Wrapped in [AnimatedSize] so the panel glides in instead of popping the
/// instant a scan turns up a second directory. AnimatedSize doesn't animate
/// its first build, so a folder whose subfolders are already known shows the
/// panel in place; one discovered a few batches into the scan slides in.
class _SubfolderPanel extends ConsumerWidget {
  const _SubfolderPanel({required this.width});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subfolders =
        ref.watch(galleryControllerProvider.select((s) => s.subfolders));
    // Show as soon as there are 2+ directory entries (including loading ones)
    // so the folder tree is visible from the moment discovery finishes.
    final visible = subfolders.length > 1;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: visible
          ? _SubfolderList(subfolders: subfolders, width: width)
          : const SizedBox.shrink(),
    );
  }
}

/// The panel's actual content — built only when there are subfolders to show,
/// so its `filter`/`totalCount` watches don't run while it's collapsed.
///
/// No right border: the slightly raised background tone separates it from the
/// grid (a hard divider line read as an out-of-place white seam).
class _SubfolderList extends ConsumerWidget {
  const _SubfolderList({required this.subfolders, required this.width});

  final List<SubfolderEntry> subfolders;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter =
        ref.watch(galleryControllerProvider.select((s) => s.subfolderFilter));
    final bestShotsOnly =
        ref.watch(galleryControllerProvider.select((s) => s.bestShotsOnly));
    final totalCount =
        ref.watch(galleryControllerProvider.select((s) => s.photos.length));
    final scanning =
        ref.watch(galleryControllerProvider.select((s) => s.scanning));
    final ctrl = ref.read(galleryControllerProvider.notifier);
    final t = ref.watch(stringsProvider);

    final hasBestShots = subfolders.any((e) => e.isBestShots && e.count > 0);
    final bestShotsCount = subfolders
        .where((e) => e.isBestShots)
        .fold<int>(0, (sum, e) => sum + e.count);
    final noFilter = filter == null && !bestShotsOnly;

    return Container(
      width: width,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          _SubfolderItem(
            icon: Icons.photo_library_outlined,
            label: t.tr('allPhotos'),
            count: totalCount > 0 ? totalCount : null,
            depth: 0,
            selected: noFilter,
            isLoading: scanning,
            onTap: () => ctrl.setSubfolderFilter(null),
          ),
          if (hasBestShots)
            _SubfolderItem(
              // Aggregate of every BestShots folder → filled white star
              // (the individual folders use a hollow one).
              icon: Icons.star_rounded,
              iconColor: Colors.white,
              label: t.tr('allBestShots'),
              count: bestShotsCount,
              depth: 0,
              selected: bestShotsOnly,
              onTap: ctrl.setBestShotsFilter,
            ),
          const Divider(height: 1),
          for (final sf in subfolders)
            _SubfolderItem(
              // BestShots folders get a hollow (outlined) star instead of a
              // folder icon.
              icon: sf.isBestShots
                  ? Icons.star_border_rounded
                  : Icons.folder_outlined,
              iconColor: sf.isBestShots ? Colors.white : null,
              // A-cut folders show the localized label ("A컷"/"A-cut"/…)
              // instead of the literal on-disk folder name.
              label: sf.isBestShots ? t.tr('aCut') : sf.label,
              // Intermediate ancestors (count 0) are non-selectable headers
              // shown only to make the nesting clear.
              count: sf.count > 0 ? sf.count : null,
              depth: sf.depth,
              selected: noFilter ? false : (!bestShotsOnly && filter == sf.dir),
              isLoading: sf.isLoading,
              onTap: sf.count > 0 ? () => ctrl.setSubfolderFilter(sf.dir) : null,
            ),
        ],
      ),
    );
  }
}

class _SubfolderItem extends StatelessWidget {
  const _SubfolderItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.depth,
    this.count,
    this.iconColor,
    this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// Indentation level — each level adds a left inset so the tree reads as a
  /// hierarchy (a child like BestShots sits to the right of its parent).
  final int depth;

  /// Trailing count; null hides it (intermediate header rows).
  final int? count;

  /// Overrides the icon tint (e.g. the amber BestShots star).
  final Color? iconColor;

  /// Tap handler; null makes the row a non-interactive header.
  final VoidCallback? onTap;

  /// When true, shows a small spinner after the count to indicate that RAW
  /// preview extraction is still in progress for this directory.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final labelColor = selected
        ? scheme.primary
        : enabled
            ? null
            : scheme.onSurfaceVariant;

    // Nested rows are inset by one level less than their depth and prefixed
    // with a 'ㄴ'-style connector (↳) so the parent → child relationship
    // reads at a glance; top-level rows have no connector.
    final indent = depth == 0 ? 12.0 : 12.0 + (depth - 1) * 16.0;
    final content = Padding(
      padding: EdgeInsets.only(
        left: indent,
        right: 12,
        top: 10,
        bottom: 10,
      ),
      child: Row(
        children: [
          if (depth > 0) ...[
            Icon(
              Icons.subdirectory_arrow_right,
              size: 16,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
          ],
          Icon(
            icon,
            size: 18,
            color: iconColor ?? (selected ? scheme.primary : labelColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: labelColor,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (isLoading) ...[
            const SizedBox(width: 5),
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    // Intermediate header: no ink/selection, just the indented label.
    if (!enabled) return content;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
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

    // Each item carries no leading dot / trailing spaces; the "·" separator
    // is a standalone widget with symmetric padding, so the gaps on either
    // side of every dot are identical regardless of locale.
    final items = <Widget>[
      Text(s.scanning
          ? t.tr('scanning')
          : t.tr('photosCount', {'count': s.total.toString()})),
      Text(t.tr('selectedCount', {'count': s.picked.toString()})),
      if (s.analyzed > 0)
        Text(t.tr('analyzedCount', {'count': s.analyzed.toString()})),
      if (s.analyzing) Text(t.tr('inferring')),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const _StatusSeparator(),
            items[i],
          ],
        ],
      ),
    );
  }
}

/// "·" divider between status-bar items, with equal padding on both sides
/// so every dot sits centered with identical left/right spacing.
class _StatusSeparator extends StatelessWidget {
  const _StatusSeparator();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·'),
      );
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
