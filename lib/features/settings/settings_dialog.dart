import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';

/// Settings dialog with a language selector and a credits section.
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

    return AlertDialog(
      title: Text(t.tr('settingsTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.tr('close')),
        ),
      ],
    );
  }
}
