import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

/// PIXELLNET theme v5 — Material 3 Dark (AI Studio aesthetic).
/// Table-row layout, hairline dividers, Google Sans Text font.
/// Light secondary auto-follows system but inherits structure from Dark.
class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  static const _radiusPill = 22.0;    // pill-buttons, chips
  static const _radiusCard = 10.0;    // input, key container
  static const _radiusChip = 16.0;    // small chips

  ColorScheme get _dark => const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: PixellnetBrand.accent,
        onPrimary: Color(0xFF131314),
        primaryContainer: PixellnetBrand.accentBg,
        onPrimaryContainer: PixellnetBrand.accent,
        secondary: PixellnetBrand.accent,
        onSecondary: Color(0xFF131314),
        tertiary: PixellnetBrand.success,
        onTertiary: Color(0xFF131314),
        error: PixellnetBrand.error,
        onError: Color(0xFF131314),
        surface: PixellnetBrand.bgSurface,
        onSurface: PixellnetBrand.textPrimary,
        surfaceContainerLowest: PixellnetBrand.bgScaffold,
        surfaceContainerLow: PixellnetBrand.bgScaffold,
        surfaceContainer: PixellnetBrand.bgSurface,
        surfaceContainerHigh: PixellnetBrand.bgElevated,
        surfaceContainerHighest: PixellnetBrand.bgElevated,
        onSurfaceVariant: PixellnetBrand.textSecondary,
        outline: PixellnetBrand.dividerStrong,
        outlineVariant: PixellnetBrand.dividerHairline,
      );

  ColorScheme get _light => const ColorScheme.light(
        brightness: Brightness.light,
        primary: PixellnetBrand.accentLight,
        onPrimary: Colors.white,
        primaryContainer: PixellnetBrand.accentBgLight,
        onPrimaryContainer: PixellnetBrand.accentLight,
        secondary: PixellnetBrand.accentLight,
        onSecondary: Colors.white,
        tertiary: PixellnetBrand.successLight,
        onTertiary: Colors.white,
        error: PixellnetBrand.errorLight,
        onError: Colors.white,
        surface: PixellnetBrand.bgSurfaceLight,
        onSurface: PixellnetBrand.textPrimaryLight,
        surfaceContainerLowest: PixellnetBrand.bgScaffoldLight,
        surfaceContainerLow: PixellnetBrand.bgScaffoldLight,
        surfaceContainer: PixellnetBrand.bgSurfaceLight,
        surfaceContainerHigh: PixellnetBrand.bgElevatedLight,
        surfaceContainerHighest: PixellnetBrand.bgElevatedLight,
        onSurfaceVariant: PixellnetBrand.textSecondaryLight,
        outline: PixellnetBrand.dividerStrongLight,
        outlineVariant: PixellnetBrand.dividerHairlineLight,
      );

  ThemeData lightTheme(ColorScheme? _) => _buildTheme(_light, Brightness.light);
  ThemeData darkTheme(ColorScheme? _) => _buildTheme(_dark, Brightness.dark);

  ThemeData _buildTheme(ColorScheme scheme, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color scaffoldBg = isDark
        ? (mode.trueBlack ? Colors.black : PixellnetBrand.bgScaffold)
        : PixellnetBrand.bgScaffoldLight;

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
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusCard)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusPill)),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline, width: 1),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusPill)),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minLeadingWidth: 0,
        shape: null,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? PixellnetBrand.accentBg : PixellnetBrand.accentBgLight,
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
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isDark ? const Color(0xFF3C4043) : const Color(0xFFDADCE0);
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? const Color(0xFF131314) : Colors.white;
          }
          return isDark ? const Color(0xFF9AA0A6) : Colors.white;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(fontFamily: fontFamily, color: scheme.onSurface, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusCard)),
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
