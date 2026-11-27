import 'dart:ui' show PlatformDispatcher;

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locale_preferences.g.dart';

/// Языки стран СНГ: раньше у каждого был свой перевод, теперь для них русский.
const _cisLanguageCodes = {'ru', 'uk', 'be', 'kk', 'ky', 'uz', 'tg', 'tk', 'az', 'hy', 'ka'};

/// Язык интерфейса по сохранённому значению (0.1.105: остались только ru и en).
///
/// Чистая функция без Riverpod: ей же пользуются места без `ref` (текст приглашения).
/// - ничего не сохранено — по языку устройства: СНГ — русский, иначе английский;
/// - сохранён язык, которого больше нет (uk, fa, zh_CN и другие) — русский.
AppLocale resolveAppLocale(String? persisted) {
  if (persisted == null) {
    final lang = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    if (_cisLanguageCodes.contains(lang)) return AppLocale.ru;
    return AppLocaleUtils.findDeviceLocale();
  }
  for (final l in AppLocale.values) {
    if (l.name == persisted) return l;
  }
  return AppLocale.ru;
}

@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences with AppLogger {
  @override
  AppLocale build() {
    final persisted = ref.watch(sharedPreferencesProvider).requireValue.getString("locale");
    final locale = resolveAppLocale(persisted);
    if (persisted != null && locale.name != persisted) {
      loggy.info("saved locale [$persisted] is no longer available, switching to [${locale.name}]");
    }
    return locale;
  }

  Future<void> changeLocale(AppLocale value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).requireValue.setString("locale", value.name);
  }
}
