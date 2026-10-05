import 'package:flutter/material.dart';

/// Brand palette: leaf green primary with earthy accents. High contrast and
/// large touch targets for outdoor, low-literacy use.
class AppTheme {
  static const seed = Color(0xFF2E7D32);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF4F7F2),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primaryContainer,
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }
}

/// Risk/severity colour scale shared by charts, badges and the map.
class RiskColors {
  static const low = Color(0xFF43A047);
  static const moderate = Color(0xFFF9A825);
  static const high = Color(0xFFEF6C00);
  static const severe = Color(0xFFC62828);
  static const none = Color(0xFF78909C);

  static Color of(String level) => switch (level) {
        'low' => low,
        'moderate' => moderate,
        'high' => high,
        'severe' => severe,
        _ => none,
      };

  static Color forRisk(double risk) => of(risk < 0.25
      ? 'low'
      : risk < 0.5
          ? 'moderate'
          : risk < 0.75
              ? 'high'
              : 'severe');
}
