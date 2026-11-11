import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  // iOS corner radii: кнопки 10, карточки/группы 10, chip 6.
  static const _radiusButton = 10.0;
  static const _radiusCard = 10.0;
  static const _radiusChip = 6.0;

  // Palette v4 (2026-11-11) — iOS Settings system colors.
  ColorScheme get _iosDark => const ColorScheme.dark(
        primary: PixellnetBrand.tintDark,
        onPrimary: Colors.white,
        primaryContainer: PixellnetBrand.tintLight,
        onPrimaryContainer: Colors.white,
        secondary: PixellnetBrand.tintDark,
        onSecondary: Colors.white,
        tertiary: PixellnetBrand.greenDark,
        onTertiary: Colors.white,
        error: PixellnetBrand.redDark,
        onError: Colors.white,
        surface: PixellnetBrand.surface,              // card bg #1C1C1E
        onSurface: PixellnetBrand.textPrimary,
        surfaceContainerLowest: PixellnetBrand.bgDark,    // scaffold #000
        surfaceContainerLow: PixellnetBrand.bgDark,
        surfaceContainer: PixellnetBrand.surface,         // table card
        surfaceContainerHigh: PixellnetBrand.surfaceElevated,
        surfaceContainerHighest: PixellnetBrand.surfaceHover,
        onSurfaceVariant: PixellnetBrand.textSecondary,
        outline: PixellnetBrand.separatorDark,
        outlineVariant: PixellnetBrand.separatorDark,
      );

  ColorScheme get _iosLight => const ColorScheme.light(
        primary: PixellnetBrand.tintLight,
        onPrimary: Colors.white,
        primaryContainer: PixellnetBrand.tintDark,
        onPrimaryContainer: Colors.white,
        secondary: PixellnetBrand.tintLight,
        onSecondary: Colors.white,
        tertiary: PixellnetBrand.greenLight,
        onTertiary: Colors.white,
        error: PixellnetBrand.redLight,
        onError: Colors.white,
        surface: PixellnetBrand.surfaceLight,              // card bg #FFFFFF
        onSurface: PixellnetBrand.textPrimaryLight,
        surfaceContainerLowest: PixellnetBrand.bgLight,    // scaffold #F2F2F7
        surfaceContainerLow: PixellnetBrand.bgLight,
        surfaceContainer: PixellnetBrand.surfaceLight,
        surfaceContainerHigh: PixellnetBrand.surfaceLight,
        surfaceContainerHighest: PixellnetBrand.surfaceLight,
        onSurfaceVariant: PixellnetBrand.textSecondaryLight,
        outline: PixellnetBrand.separatorLight,
        outlineVariant: PixellnetBrand.separatorLight,
      );

  ThemeData lightTheme(ColorScheme? _) => _buildTheme(_iosLight, Brightness.light);
  ThemeData darkTheme(ColorScheme? _) => _buildTheme(_iosDark, Brightness.dark);

  ThemeData _buildTheme(ColorScheme scheme, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    // scaffold = системный grouped-table фон (отличается от карточек).
    final Color scaffoldBg = isDark
        ? (mode.trueBlack ? Colors.black : PixellnetBrand.bgDark)
        : PixellnetBrand.bgLight;
    final Color cardBg = isDark ? PixellnetBrand.surface : PixellnetBrand.surfaceLight;

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
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          // iOS не использует letterSpacing в tytle, убрано.
        ),
        iconTheme: IconThemeData(color: scheme.primary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusCard)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusButton)),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1),
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusButton)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: scheme.onSurface,
        tileColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusChip)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5, // iOS hairline (1px @2x)
        space: 0.5,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          color: scheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusChip)),
        side: BorderSide.none,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardBg,
        contentTextStyle: TextStyle(fontFamily: fontFamily, color: scheme.onSurface, fontSize: 15),
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
