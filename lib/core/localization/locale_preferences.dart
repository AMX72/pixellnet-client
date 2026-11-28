import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'locale_preferences.g.dart';

/// Язык интерфейса по сохранённому значению (T-026, шаг 5: снова все 21 язык).
///
/// Чистая функция без Riverpod: ей же пользуются места без `ref` (текст приглашения).
/// - сохранён язык (любой из 21) — открывается он, замены на русский нет;
/// - ничего не сохранено — язык устройства, если он среди 21; иначе, как в 0.1.104, запасной (английский);
/// - сохранено значение, которого нет в списке, — английский, как в 0.1.104.
AppLocale resolveAppLocale(String? persisted) {
  if (persisted == null) return AppLocaleUtils.findDeviceLocale();
  // keep backward compatibility with chinese after changing zh to zh_CN
  if (persisted == "zh") return AppLocale.zhCn;
  for (final l in AppLocale.values) {
    if (l.name == persisted) return l;
  }
  return AppLocale.en;
}

/// Тексты языка, сохранённого в настройках, — для кода без `ref` и без `BuildContext` (службы).
Future<Translations> translationsFromPrefs(SharedPreferences prefs) =>
    resolveAppLocale(prefs.getString("locale")).build();

@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences with AppLogger {
  @override
  AppLocale build() {
    final persisted = ref.watch(sharedPreferencesProvider).requireValue.getString("locale");
    final locale = resolveAppLocale(persisted);
    if (persisted != null && persisted != "zh" && locale.name != persisted) {
      loggy.error("error setting locale: [$persisted]");
    }
    return locale;
  }

  Future<void> changeLocale(AppLocale value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).requireValue.setString("locale", value.name);
  }
}
