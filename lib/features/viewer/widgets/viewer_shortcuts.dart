import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intents + shortcuts for the loupe/detail viewer. Mirrors the gallery
/// shortcut set but adds Esc-to-close (and Enter as a synonym for close,
/// matching the open/close symmetry users expect from Lightroom).

class MoveViewerIntent extends Intent {
  const MoveViewerIntent(this.delta);
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

class CloseViewerIntent extends Intent {
  const CloseViewerIntent();
}

class ViewerShortcuts extends StatelessWidget {
  const ViewerShortcuts({
    super.key,
    required this.onMove,
    required this.onExtendSelection,
    required this.onAddSelection,
    required this.onTogglePick,
    required this.onClose,
    required this.child,
  });

  final void Function(int delta) onMove;
  final void Function(int delta) onExtendSelection;
  final void Function(int delta) onAddSelection;
  final VoidCallback onTogglePick;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): MoveViewerIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): MoveViewerIntent(1),
        // Shift+Arrow — extend the contiguous range selection.
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            ExtendSelectionIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            ExtendSelectionIntent(1),
        // Ctrl/Cmd+Arrow — move cursor and add the focused photo to selection.
        SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            AddSelectionIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            AddSelectionIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
            AddSelectionIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight, meta: true):
            AddSelectionIntent(1),
        SingleActivator(LogicalKeyboardKey.space): TogglePickIntent(),
        SingleActivator(LogicalKeyboardKey.escape): CloseViewerIntent(),
        SingleActivator(LogicalKeyboardKey.enter): CloseViewerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          MoveViewerIntent: CallbackAction<MoveViewerIntent>(
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
          CloseViewerIntent: CallbackAction<CloseViewerIntent>(
            onInvoke: (_) {
              onClose();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
