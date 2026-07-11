import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  static const _radiusButton = 12.0;
  static const _radiusCard = 16.0;
  static const _radiusChip = 6.0;

  // Palette v3 — единая warm/mocha схема для light и dark.
  // Light theme в MVP не используется, но описан для совместимости.
  ColorScheme get _v3Dark => const ColorScheme.dark(
        primary: PixellnetBrand.mocha,
        onPrimary: Color(0xFF1A1917),
        primaryContainer: PixellnetBrand.mochaDark,
        onPrimaryContainer: PixellnetBrand.textPrimary,
        secondary: PixellnetBrand.amber,
        onSecondary: Color(0xFF1A1917),
        tertiary: PixellnetBrand.olive,
        onTertiary: Color(0xFF1A1917),
        error: PixellnetBrand.coral,
        onError: Color(0xFF1A1917),
        surface: PixellnetBrand.surface,
        onSurface: PixellnetBrand.textPrimary,
        surfaceContainerLowest: PixellnetBrand.bgDark,
        surfaceContainerLow: PixellnetBrand.surface,
        surfaceContainer: PixellnetBrand.surfaceElevated,
        surfaceContainerHigh: PixellnetBrand.surfaceElevated,
        surfaceContainerHighest: PixellnetBrand.surfaceHover,
        onSurfaceVariant: PixellnetBrand.textSecondary,
        outline: PixellnetBrand.textMuted,
        outlineVariant: Color(0xFF3C3A36),
      );

  ColorScheme get _v3Light => const ColorScheme.light(
        primary: PixellnetBrand.mochaDark,
        onPrimary: Color(0xFFFFFDF9),
        secondary: PixellnetBrand.mocha,
        onSecondary: Color(0xFFFFFDF9),
        tertiary: PixellnetBrand.olive,
        error: PixellnetBrand.coral,
        surface: Color(0xFFF7F3EC),
        onSurface: Color(0xFF1A1917),
      );

  ThemeData lightTheme(ColorScheme? _) {
    return _buildTheme(_v3Light, Brightness.light);
  }

  ThemeData darkTheme(ColorScheme? _) {
    return _buildTheme(_v3Dark, Brightness.dark);
  }

  ThemeData _buildTheme(ColorScheme scheme, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color scaffoldBg = isDark
        ? (mode.trueBlack ? Colors.black : PixellnetBrand.bgDark)
        : scheme.surface;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: scaffoldBg,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.primary, size: 24),
      ),
      cardTheme: CardThemeData(
        color: isDark ? PixellnetBrand.surfaceElevated : scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusCard)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusButton)),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.5),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusButton)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusChip)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.secondary.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          color: scheme.secondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusChip)),
        side: BorderSide.none,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PixellnetBrand.surfaceElevated,
        contentTextStyle: TextStyle(fontFamily: fontFamily, color: scheme.onSurface, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusButton)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.black => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);
    final defaultMaterialTheme = isDark ? darkTheme(darkColorScheme) : lightTheme(lightColorScheme);
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ).copyWith(),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: def.scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
