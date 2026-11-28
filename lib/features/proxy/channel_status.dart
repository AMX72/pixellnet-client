import 'package:hiddify/gen/translations.g.dart';

/// Подпись состояния канала по задержке — вариант «В» (решение владельца 28.11):
/// «Работает» / «Не отвечает» / «Проверяем связь…» вместо «Быстрый / Обычный / Медленный»
/// (у всех каналов скорость почти одна). Миллисекунды показываются отдельно, в подпись их не дублируем.
///
/// - задержка больше 0 и меньше 65000 — канал ответил;
/// - 65000 и больше — ответа нет;
/// - 0 и меньше — ещё не проверяли.
String channelStatusLabel(Translations t, int delayMs) {
  if (delayMs <= 0) return t.pages.home.channelChecking;
  if (delayMs >= 65000) return t.pages.home.channelNotResponding;
  return t.pages.home.channelWorking;
}

/// Название страны по коду (DE, NL…) на языке приложения; для неизвестного кода — пустая строка.
String countryName(Translations t, String code) {
  final c = t.ui.country;
  return switch (code.toUpperCase()) {
    'DE' => c.de,
    'NL' => c.nl,
    'LT' => c.lt,
    'FI' => c.fi,
    'FR' => c.fr,
    'SE' => c.se,
    'US' => c.us,
    'GB' => c.gb,
    'CH' => c.ch,
    'AT' => c.at,
    'PL' => c.pl,
    'CZ' => c.cz,
    'RU' => c.ru,
    'UA' => c.ua,
    'BY' => c.by,
    'KZ' => c.kz,
    'TR' => c.tr,
    _ => '',
  };
}
