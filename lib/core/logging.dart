import 'dart:developer' as developer;

import 'package:logging/logging.dart';

void initLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((rec) {
    developer.log(
      rec.message,
      time: rec.time,
      level: rec.level.value,
      name: rec.loggerName,
      error: rec.error,
      stackTrace: rec.stackTrace,
    );
  });
}
