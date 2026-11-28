import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Стандартные тексты Flutter (подсказка «Назад», окна, календарь) есть не для всех наших языков:
/// для таджикского (tg) и туркменского (tk) их нет. Без запасного перевода Material-виджеты
/// (AppBar, нижние окна, поля ввода) на этих языках падают с «No MaterialLocalizations found».
/// Запасные делегаты берут для таких языков стандартные тексты на русском (T-026, шаг 5).
class _FallbackDelegate<T> extends LocalizationsDelegate<T> {
  const _FallbackDelegate(this._base, this._fallback);

  final LocalizationsDelegate<T> _base;
  final Locale _fallback;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => _base.isSupported(locale) ? _base.load(locale) : _base.load(_fallback);

  @override
  bool shouldReload(_FallbackDelegate<T> old) => false;
}

const _fallbackLocale = Locale('ru');

/// Делегаты для `MaterialApp`: сначала настоящие, затем запасные — они срабатывают только там,
/// где настоящий перевод для языка не поддерживается.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  ...GlobalMaterialLocalizations.delegates,
  _FallbackDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate, _fallbackLocale),
  _FallbackDelegate<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate, _fallbackLocale),
];
