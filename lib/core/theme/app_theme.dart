import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  /// PIXELLNET palette v2 (индирго + сейдж, мягкие цвета).
  /// Явно строим `ColorScheme(...)` — иначе `fromSeed` перегенерит tonal palette
  /// и перекроет наши sage-accent и off-black surface.
  ThemeData lightTheme(ColorScheme? lightColorScheme) {
    final ColorScheme scheme = lightColorScheme ??
        const ColorScheme(
          brightness: Brightness.light,
          primary: PixellnetColors.lightPrimary,             // коричневый
          onPrimary: PixellnetColors.lightOnPrimary,
          primaryContainer: PixellnetColors.lightPrimaryContainer,
          onPrimaryContainer: PixellnetColors.lightOnPrimaryContainer,
          secondary: PixellnetColors.lightAccent,            // жёлтый
          onSecondary: PixellnetColors.lightOnAccent,
          tertiary: PixellnetColors.lightTertiary,           // голубой
          onTertiary: PixellnetColors.lightOnTertiary,
          tertiaryContainer: PixellnetColors.lightTertiaryContainer,
          onTertiaryContainer: PixellnetColors.lightOnTertiaryContainer,
          error: PixellnetColors.danger,
          onError: PixellnetColors.onDanger,
          surface: PixellnetColors.lightSurface,
          onSurface: PixellnetColors.lightOnSurface,
          surfaceContainer: PixellnetColors.lightSurfaceContainer,
          surfaceContainerHighest: PixellnetColors.lightSurfaceContainerHigh,
          onSurfaceVariant: PixellnetColors.lightOnSurfaceVariant,
          outline: PixellnetColors.lightOutline,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  ThemeData darkTheme(ColorScheme? darkColorScheme) {
    final ColorScheme scheme = darkColorScheme ??
        const ColorScheme(
          brightness: Brightness.dark,
          primary: PixellnetColors.darkPrimary,              // коричневый
          onPrimary: PixellnetColors.darkOnPrimary,
          primaryContainer: PixellnetColors.darkPrimaryContainer,
          onPrimaryContainer: PixellnetColors.darkOnPrimaryContainer,
          secondary: PixellnetColors.darkAccent,             // жёлтый
          onSecondary: PixellnetColors.darkOnAccent,
          tertiary: PixellnetColors.darkTertiary,            // голубой
          onTertiary: PixellnetColors.darkOnTertiary,
          tertiaryContainer: PixellnetColors.darkTertiaryContainer,
          onTertiaryContainer: PixellnetColors.darkOnTertiaryContainer,
          error: PixellnetColors.danger,
          onError: PixellnetColors.onDanger,
          surface: PixellnetColors.darkSurface,
          onSurface: PixellnetColors.darkOnSurface,
          surfaceContainer: PixellnetColors.darkSurfaceContainer,
          surfaceContainerHighest: PixellnetColors.darkSurfaceContainerHigh,
          onSurfaceVariant: PixellnetColors.darkOnSurfaceVariant,
          outline: PixellnetColors.darkOutline,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mode.trueBlack ? Colors.black : scheme.surface,
      fontFamily: fontFamily,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
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
    // final def = CupertinoThemeData(brightness: Brightness.dark);

    // return def;
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
