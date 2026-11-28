import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  String get preferredFontFamily =>
      this == AppLocale.fa ? FontFamily.shabnam : (kIsWeb || !Platform.isWindows ? "" : FontFamily.emoji);

  /// Названия языков в списке выбора. Первые 11 строк — как в 0.1.104; названия для 10 языков СНГ
  /// (az, be, hy, ka, kk, ky, tg, tk, uk, uz) добавлены в 0.1.106: в 0.1.104 для них показывалось «Unknown».
  /// Те же названия на главном экране — `_localeLabel` в `home_page.dart`.
  String get localeName => switch (flutterLocale.toString()) {
    "ar" => "العربية",
    "az" => "Azərbaycanca",
    "be" => "Беларуская",
    "en" => "English",
    "es" => "Spanish",
    "fa" => "فارسی",
    "fr" => "Français",
    "hy" => "Հայերեն",
    "id" => "Indonesian",
    "ka" => "ქართული",
    "kk" => "Қазақша",
    "ky" => "Кыргызча",
    "pt_BR" => "Portuguese (Brazil)",
    "ru" => "Русский",
    "tg" => "Тоҷикӣ",
    "tk" => "Türkmençe",
    "tr" => "Türkçe",
    "uk" => "Українська",
    "uz" => "Oʻzbekcha",
    "zh" || "zh_CN" => "中文 (中国)",
    "zh_TW" => "中文 (台湾)",
    _ => "Unknown",
  };

  bool get isRussian => this == AppLocale.ru;
}
