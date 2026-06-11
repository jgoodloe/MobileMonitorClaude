import 'package:flutter/material.dart';

/// Centralized theming with light and dark variants. The original hardcoded a
/// single blue seed and didn't support dark mode.
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF1565C0);

  static ThemeData light() => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      );

  static ThemeData dark() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
}

/// Status-driven colors resolved against the active scheme.
class StatusColors {
  const StatusColors._();

  static Color forStatus(BuildContext context, bool? up) {
    final scheme = Theme.of(context).colorScheme;
    if (up == null) return scheme.outline;
    return up ? const Color(0xFF2E7D32) : scheme.error;
  }
}
