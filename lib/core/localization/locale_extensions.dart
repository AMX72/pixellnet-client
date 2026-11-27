import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  String get preferredFontFamily => kIsWeb || !Platform.isWindows ? "" : FontFamily.emoji;

  /// Только ru и en (0.1.105, решение Р0.6).
  String get localeName => switch (flutterLocale.toString()) {
    "en" => "English",
    "ru" => "Русский",
    _ => "Unknown",
  };

  bool get isRussian => this == AppLocale.ru;
}
