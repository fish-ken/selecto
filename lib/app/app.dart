import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class SelectoApp extends StatelessWidget {
  const SelectoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Selecto',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
