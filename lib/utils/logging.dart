import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Single place to configure logging. Replaces the ~150 raw `print()`
/// statements in the original, which executed on every CRL parse (including
/// the release build) and added measurable overhead plus log noise.
///
/// In debug builds, records are forwarded to the console. In release builds
/// the listener is not attached, so logging is effectively free.
void setupLogging() {
  Logger.root.level = kDebugMode ? Level.ALL : Level.WARNING;
  if (kDebugMode) {
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      debugPrint('${record.level.name}: ${record.loggerName}: ${record.message}');
    });
  }
}

Logger appLogger(String name) => Logger(name);
