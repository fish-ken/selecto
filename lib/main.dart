import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/logging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(960, 640));
  await windowManager.setTitle('Selecto');

  runApp(const ProviderScope(child: SelectoApp()));
}
