import 'package:flutter/material.dart';

/// Global App Theme Scaffold
///
/// Centralizes theming so feature code and widgets avoid ad‑hoc style choices.
/// Keep this file lean; expose only stable entrypoints.
///
/// Design Goals:
/// - Single source of truth for color, typography, shape, spacing tokens.
/// - Support light + dark variants with a shared semantic token layer.
/// - Fast iteration: changing seed or tokens updates entire UI.
/// - Avoid premature over‑abstraction (no design system DSL yet).
///
/// Non-Goals (MVP):
/// - Dynamic runtime theme editing (can be added later via a provider).
/// - Full design token export pipeline.
/// - High‑contrast / accessibility variants (plan later—ensure base is readable).
///
/// References:
/// - docs/ui/features.md
/// - codestyle.md (for general code style principles)
///
/// Usage:
///   MaterialApp(
///     theme: AppTheme.light(),
///     darkTheme: AppTheme.dark(),
///     themeMode: ThemeMode.system,
///     ...
///   )
///
/// Add new shared styles as semantic getters (e.g., AppTheme.elevationSmall)
/// instead of duplicating magic values inside widgets.
final class AppTheme {
  AppTheme._();

  /// Primary brand / seed color (tweak with product/design input).
  static const Color _seed = Color(0xFF5B4BFF); // Deep indigo-violet

  /// Secondary accent used sparingly (chips, highlights).
  static const Color _accent = Color(0xFFFFB347); // Warm amber accent

  /// Common radius tokens.
  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radiusMedium = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(16));

  /// Elevation tokens (centralize for consistent layering).
  static const double elevationLow = 1;
  static const double elevationMid = 3;
  static const double elevationHigh = 6;

  /// Spacing scale (could be migrated to a dedicated tokens file later).
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;

  /// Light theme entrypoint.
  static ThemeData light({bool enableMaterial3 = true}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );

    return _baseTheme(
      colorScheme: scheme,
      enableMaterial3: enableMaterial3,
      brightness: Brightness.light,
    );
  }

  /// Dark theme entrypoint.
  static ThemeData dark({bool enableMaterial3 = true}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );

    return _baseTheme(
      colorScheme: scheme,
      enableMaterial3: enableMaterial3,
      brightness: Brightness.dark,
    );
  }

  /// Internal shared base adjustments.
  static ThemeData _baseTheme({
    required ColorScheme colorScheme,
    required bool enableMaterial3,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;

    final textTheme = _textThemeMerge(
      base: Typography.material2021(platform: TargetPlatform.android)
          .englishLike
          .merge(Typography.material2021().black),
      color: isDark ? Colors.white : Colors.black87,
    );

    return ThemeData(
      useMaterial3: enableMaterial3,
      colorScheme: colorScheme,
      brightness: brightness,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF111216) : const Color(0xFFF8F9FB),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: elevationLow,
          shape: RoundedRectangleBorder(borderRadius: radiusMedium),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radiusMedium),
          side: BorderSide(color: colorScheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: radiusMedium,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMedium,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: radiusSmall),
        labelStyle: textTheme.labelMedium!,
        selectedColor: colorScheme.secondaryContainer,
        backgroundColor: colorScheme.surfaceVariant,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      cardTheme: CardThemeData(
        elevation: elevationLow,
        shape: RoundedRectangleBorder(borderRadius: radiusLarge),
        margin: const EdgeInsets.all(space8),
      ),
      dividerTheme: DividerThemeData(
        thickness: 1,
        color: colorScheme.outlineVariant.withOpacity(0.5),
        space: space16,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
      extensions: <ThemeExtension<dynamic>>[
        _AppAccentColors(
          accent: _accent,
          accentOn: _contrastForeground(_accent),
        ),
      ],
    );
  }

  /// Merge and apply uniform foreground color to a base text theme.
  static TextTheme _textThemeMerge({
    required TextTheme base,
    required Color color,
  }) {
    return base.apply(
      bodyColor: color,
      displayColor: color,
      decorationColor: color,
    );
  }

  /// Provide readable text color for a background fill.
  static Color _contrastForeground(Color bg) {
    // Standard luminance heuristic.
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  /// Retrieve accent colors extension.
  static _AppAccentColors accentColors(BuildContext context) =>
      Theme.of(context).extension<_AppAccentColors>()!;
}

/// Custom theme extension for secondary accent palette.
/// Keep minimal; extend cautiously.
@immutable
class _AppAccentColors extends ThemeExtension<_AppAccentColors> {
  final Color accent;
  final Color accentOn;

  const _AppAccentColors({
    required this.accent,
    required this.accentOn,
  });

  @override
  _AppAccentColors copyWith({Color? accent, Color? accentOn}) =>
      _AppAccentColors(
        accent: accent ?? this.accent,
        accentOn: accentOn ?? this.accentOn,
      );

  @override
  _AppAccentColors lerp(ThemeExtension<_AppAccentColors>? other, double t) {
    if (other is! _AppAccentColors) return this;
    return _AppAccentColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentOn: Color.lerp(accentOn, other.accentOn, t)!,
    );
  }
}