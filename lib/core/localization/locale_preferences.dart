import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hiddify/core/localization/plural_rules.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'locale_preferences.g.dart';

/// Язык устройства среди языков приложения; нет в списке — английский.
///
/// Свой разбор вместо `AppLocaleUtils.findDeviceLocale()`: тот при неизвестном языке без страны берёт
/// «первый язык без страны» из списка, то есть результат зависит от порядка в перечислении.
/// У нас у всех 12 языков страны нет, сравнивается только код языка.
AppLocale deviceAppLocale([Locale? device]) {
  final code = (device ?? WidgetsBinding.instance.platformDispatcher.locale).languageCode;
  for (final l in AppLocale.values) {
    if (l.languageCode == code) return l;
  }
  return AppLocale.en;
}

/// Язык интерфейса по сохранённому значению (0.1.106, 12 языков: ru, en, kk, ky, uk, be, az, hy, ka, tg, tk, uz).
///
/// Чистая функция без Riverpod: ей же пользуются места без `ref` (текст приглашения).
/// - сохранён язык из 12 — открывается он;
/// - сохранён убранный язык (ar, es, fa, fr, id, pt-BR, tr, zh, zh-CN, zh-TW) или любое незнакомое значение — английский;
/// - ничего не сохранено — язык устройства, если он среди 12; иначе английский.
AppLocale resolveAppLocale(String? persisted, {Locale? device}) {
  if (persisted == null) return deviceAppLocale(device);
  for (final l in AppLocale.values) {
    if (l.name == persisted) return l;
  }
  return AppLocale.en;
}

/// Тексты языка, сохранённого в настройках, — для кода без `ref` и без `BuildContext` (службы).
Future<Translations> translationsFromPrefs(SharedPreferences prefs) =>
    resolveAppLocale(prefs.getString("locale")).buildTranslations();

@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences with AppLogger {
  @override
  AppLocale build() {
    final prefs = ref.watch(sharedPreferencesProvider).requireValue;
    final persisted = prefs.getString("locale");
    final locale = resolveAppLocale(persisted);
    if (persisted != null && locale.name != persisted) {
      // Сохранён язык, которого в приложении больше нет: открываем английский и перезаписываем значение,
      // чтобы не разбирать его при каждом запуске.
      loggy.info("saved locale [$persisted] is not supported anymore, switching to [${locale.name}]");
      unawaited(prefs.setString("locale", locale.name));
    }
    return locale;
  }

  Future<void> changeLocale(AppLocale value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).requireValue.setString("locale", value.name);
  }
}
