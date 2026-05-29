import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of the modifier keys that affect grid selection.
@immutable
class ModifierKeys {
  const ModifierKeys({
    this.ctrl = false,
    this.shift = false,
    this.meta = false,
  });

  final bool ctrl;
  final bool shift;
  final bool meta;

  /// The "toggle / add-to-selection" modifier: Ctrl on Windows/Linux, Cmd
  /// (Meta) on macOS. Deliberately does NOT treat the Windows key as a
  /// selection modifier on Windows — pressing it opens the Start menu and
  /// its key-up is lost, which used to leave the app stuck in multi-select.
  bool get toggleSelect =>
      defaultTargetPlatform == TargetPlatform.macOS ? meta : ctrl;

  ModifierKeys copyWith({bool? ctrl, bool? shift, bool? meta}) => ModifierKeys(
        ctrl: ctrl ?? this.ctrl,
        shift: shift ?? this.shift,
        meta: meta ?? this.meta,
      );
}

// Not `const`: LogicalKeyboardKey overrides `==`/`hashCode`, which const
// sets disallow. Top-level `final` is initialized once, lazily.
final _ctrlKeys = {
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
};
final _shiftKeys = {
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};
final _metaKeys = {
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

/// Tracks modifier-key state from the raw key-event stream rather than
/// reading [HardwareKeyboard]'s accumulated state at click time.
///
/// Why: the accumulated state goes stale whenever a key-up is missed, which
/// happens every time the window loses focus while a modifier is held
/// (Alt+Tab, the Windows key, a native file dialog). That left plain clicks
/// being misread as Ctrl+clicks → unwanted multi-selection. We instead
/// maintain our own flags AND [reset] them on window blur, so a lost key-up
/// can never strand a modifier in the "pressed" state.
class ModifierKeysNotifier extends Notifier<ModifierKeys> {
  @override
  ModifierKeys build() => const ModifierKeys();

  /// Feed one raw key event. Never consumes it (always returns false), so
  /// this composes safely as a global [HardwareKeyboard] handler.
  bool handle(KeyEvent event) {
    final bool down;
    if (event is KeyDownEvent) {
      down = true;
    } else if (event is KeyUpEvent) {
      down = false;
    } else {
      return false; // ignore repeats / synthesized
    }

    final key = event.logicalKey;
    if (_ctrlKeys.contains(key)) {
      if (state.ctrl != down) state = state.copyWith(ctrl: down);
    } else if (_shiftKeys.contains(key)) {
      if (state.shift != down) state = state.copyWith(shift: down);
    } else if (_metaKeys.contains(key)) {
      if (state.meta != down) state = state.copyWith(meta: down);
    }
    return false;
  }

  /// Clear all modifiers. Called when the window loses focus so a missed
  /// key-up doesn't strand the app in multi-select mode.
  void reset() {
    if (state.ctrl || state.shift || state.meta) {
      state = const ModifierKeys();
    }
  }
}

final modifierKeysProvider =
    NotifierProvider<ModifierKeysNotifier, ModifierKeys>(
  ModifierKeysNotifier.new,
);
