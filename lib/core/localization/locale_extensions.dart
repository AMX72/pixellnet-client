import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

/// Языки приложения в порядке списка выбора (решение владельца, 28.11, T-026): русский (основной),
/// английский, затем языки СНГ по алфавиту их русских названий: азербайджанский, армянский, белорусский,
/// грузинский, казахский, киргизский, таджикский, туркменский, узбекский, украинский.
/// Тест `locale_order_test.dart` следит, чтобы здесь были ровно все языки из `assets/translations`.
const List<AppLocale> kAppLocalesInListOrder = [
  AppLocale.ru,
  AppLocale.en,
  AppLocale.az,
  AppLocale.hy,
  AppLocale.be,
  AppLocale.ka,
  AppLocale.kk,
  AppLocale.ky,
  AppLocale.tg,
  AppLocale.tk,
  AppLocale.uz,
  AppLocale.uk,
];

extension AppLocaleX on AppLocale {
  // Шрифт для персидского (Shabnam) больше не нужен: персидского языка в приложении нет (с 0.1.106, 12 языков).
  String get preferredFontFamily => kIsWeb || !Platform.isWindows ? "" : FontFamily.emoji;

  /// Названия языков (на самих языках) в списке выбора: настройки, первый экран, главный экран.
  String get localeName => switch (languageCode) {
    "az" => "Azərbaycanca",
    "be" => "Беларуская",
    "en" => "English",
    "hy" => "Հայերեն",
    "ka" => "ქართული",
    "kk" => "Қазақша",
    "ky" => "Кыргызча",
    "ru" => "Русский",
    "tg" => "Тоҷикӣ",
    "tk" => "Türkmençe",
    "uk" => "Українська",
    "uz" => "Oʻzbekcha",
    _ => "Unknown",
  };

  bool get isRussian => this == AppLocale.ru;
}
