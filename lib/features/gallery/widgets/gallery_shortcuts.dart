import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent + action plumbing for the gallery shortcuts. Using the
/// Shortcuts/Actions/Focus widgets (rather than RawKeyboardListener) so
/// the bindings respect focus traversal and survive platform input quirks.

class MoveCursorIntent extends Intent {
  const MoveCursorIntent(this.delta);
  final int delta;
}

/// Shift+Arrow — extend the contiguous range selection by [delta].
class ExtendSelectionIntent extends Intent {
  const ExtendSelectionIntent(this.delta);
  final int delta;
}

/// Ctrl/Cmd+Arrow — move the cursor by [delta] and add the focused photo
/// to the selection (keeps the existing selection).
class AddSelectionIntent extends Intent {
  const AddSelectionIntent(this.delta);
  final int delta;
}

class TogglePickIntent extends Intent {
  const TogglePickIntent();
}

class PickAllIntent extends Intent {
  const PickAllIntent();
}

class UnpickAllIntent extends Intent {
  const UnpickAllIntent();
}

class OpenViewerIntent extends Intent {
  const OpenViewerIntent();
}

class GalleryShortcuts extends StatelessWidget {
  const GalleryShortcuts({
    super.key,
    required this.crossAxisCount,
    required this.onMove,
    required this.onExtendSelection,
    required this.onAddSelection,
    required this.onTogglePick,
    required this.onPickAll,
    required this.onUnpickAll,
    required this.onOpenViewer,
    required this.child,
  });

  final int crossAxisCount;
  final void Function(int delta) onMove;
  final void Function(int delta) onExtendSelection;
  final void Function(int delta) onAddSelection;
  final VoidCallback onTogglePick;
  final VoidCallback onPickAll;
  final VoidCallback onUnpickAll;
  final VoidCallback onOpenViewer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const MoveCursorIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const MoveCursorIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            MoveCursorIntent(-crossAxisCount),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            MoveCursorIntent(crossAxisCount),
        // Shift+Arrow — extend the contiguous range selection.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const ExtendSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const ExtendSelectionIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
            ExtendSelectionIntent(-crossAxisCount),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
            ExtendSelectionIntent(crossAxisCount),
        // Ctrl/Cmd+Arrow — move cursor and add the focused photo to selection.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const AddSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const AddSelectionIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
            AddSelectionIntent(-crossAxisCount),
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
            AddSelectionIntent(crossAxisCount),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
            const AddSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true):
            const AddSelectionIntent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
            AddSelectionIntent(-crossAxisCount),
        const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
            AddSelectionIntent(crossAxisCount),
        const SingleActivator(LogicalKeyboardKey.space): const TogglePickIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const OpenViewerIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): const PickAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): const PickAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): const UnpickAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): const UnpickAllIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          MoveCursorIntent: CallbackAction<MoveCursorIntent>(
            onInvoke: (intent) {
              onMove(intent.delta);
              return null;
            },
          ),
          ExtendSelectionIntent: CallbackAction<ExtendSelectionIntent>(
            onInvoke: (intent) {
              onExtendSelection(intent.delta);
              return null;
            },
          ),
          AddSelectionIntent: CallbackAction<AddSelectionIntent>(
            onInvoke: (intent) {
              onAddSelection(intent.delta);
              return null;
            },
          ),
          TogglePickIntent: CallbackAction<TogglePickIntent>(
            onInvoke: (_) {
              onTogglePick();
              return null;
            },
          ),
          PickAllIntent: CallbackAction<PickAllIntent>(
            onInvoke: (_) {
              onPickAll();
              return null;
            },
          ),
          UnpickAllIntent: CallbackAction<UnpickAllIntent>(
            onInvoke: (_) {
              onUnpickAll();
              return null;
            },
          ),
          OpenViewerIntent: CallbackAction<OpenViewerIntent>(
            onInvoke: (_) {
              onOpenViewer();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
