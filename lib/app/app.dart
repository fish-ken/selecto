import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'router.dart';
import 'theme.dart';

class SelectoApp extends ConsumerWidget {
  const SelectoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider).locale;

    return MaterialApp.router(
      title: 'Selecto',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _AppScrollBehavior(),
      locale: locale,
      supportedLocales: [for (final l in AppLocale.values) l.locale],
      // Supplies MaterialLocalizations/CupertinoLocalizations for every
      // supported locale. Without these, Material widgets crash for `ko`.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

/// Lets scroll views be dragged with the mouse, not just the wheel/trackpad.
/// Flutter's default desktop behavior omits [PointerDeviceKind.mouse] from
/// drag devices; adding it enables click-and-drag scrolling for the photo
/// grid (vertical) and the viewer filmstrip (horizontal).
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
