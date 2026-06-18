import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/glass.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/l10n.dart';

/// Settings dialog with a language selector and a credits section.
/// Rendered as a frosted Liquid Glass card centered over a dimmed backdrop.
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  /// Convenience launcher.
  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const SettingsDialog(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassSurface(
          radius: 24,
          blur: 18,
          thickness: 24,
          padding: const EdgeInsets.all(24),
          child: _content(context, ref, t),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, AppStrings t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.tr('settingsTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
          Row(
            children: [
              Text(t.tr('language')),
              const SizedBox(width: 16),
              DropdownButton<AppLocale>(
                value: ref.watch(localeControllerProvider),
                items: [
                  for (final l in AppLocale.values)
                    DropdownMenuItem<AppLocale>(
                      value: l,
                      child: Text(l.label),
                    ),
                ],
                onChanged: (l) {
                  if (l != null) {
                    ref.read(localeControllerProvider.notifier).set(l);
                  }
                },
              ),
            ],
          ),
        const SizedBox(height: 24),
        Text(
          t.tr('credits'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SelectableText(t.tr('creditsBody')),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.tr('close')),
          ),
        ),
      ],
    );
  }
}
