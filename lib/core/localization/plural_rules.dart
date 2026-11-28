import 'package:hiddify/gen/translations.g.dart';

// Правила множественного числа (T-026, 28.11).
//
// В slang 4.8.1 встроены правила только для cs, de, en, es, fr, it, ja, pl, ru, sv, uk, vi
// (`plural_resolver_map.dart`). Для остальных языков slang пишет в журнал «Resolver … not specified»
// и берёт запасное правило «0 → zero/other, 1 → one/other, иначе other». Для белорусского (be) этого мало:
// формы `few` и `many` не выбирались бы вообще («2 дзень» вместо «2 дні»).
//
// У нас `locale_handling: false`, поэтому класса `LocaleSettings` с `setPluralResolver` нет. Он только
// вызывает `AppLocale.build(cardinalResolver: ...)` — так же делаем и мы, в `AppLocaleTranslations.buildTranslations`.
// Все места, где собираются тексты языка, обязаны брать `buildTranslations()`, а не `build()`.

/// CLDR для белорусского и украинского (как у русского): one / few / many / other.
/// - one: остаток от деления на 10 равен 1, остаток от деления на 100 не равен 11 («1 день», «21 день»);
/// - few: остаток на 10 от 2 до 4, остаток на 100 не от 12 до 14 («2 дня», «23 дня»);
/// - many: всё остальное у целых, включая 0 («0 дней», «5 дней», «11 дней»);
/// - other: дробные числа.
/// Встроенное правило slang для украинского отдаёт для 0 форму `other` («0 дня» вместо «0 днів»),
/// поэтому украинский тоже здесь. Русский остаётся на встроенном правиле: у него `other` и `many` совпадают.
String _slavicCardinal(num n, {String? zero, String? one, String? two, String? few, String? many, String? other}) {
  if (n != n.truncate()) return other ?? n.toString();
  final i = n.abs().toInt();
  if (i == 0 && zero != null) return zero;
  final r10 = i % 10;
  final r100 = i % 100;
  if (r10 == 1 && r100 != 11) return one ?? other ?? n.toString();
  if (r10 >= 2 && r10 <= 4 && (r100 < 12 || r100 > 14)) return few ?? other ?? n.toString();
  return many ?? other ?? n.toString();
}

/// CLDR для языков с двумя формами: one — число 1, other — остальные.
/// az, ka, kk, ky, tk, uz — «n = 1»; таджикский (tg) в CLDR без отдельной формы — для него то же правило безвредно,
/// переводчик может дать одинаковые `one` и `other`.
String _oneOtherCardinal(num n, {String? zero, String? one, String? two, String? few, String? many, String? other}) {
  if (n == 0 && zero != null) return zero;
  if (n == 1) return one ?? other ?? n.toString();
  return other ?? n.toString();
}

/// Армянский (CLDR): one — 0 и 1 («0 օր», «1 օր»), other — остальные.
String _armenianCardinal(num n, {String? zero, String? one, String? two, String? few, String? many, String? other}) {
  if (n == 0 && zero != null) return zero;
  if (n == 0 || n == 1) return one ?? other ?? n.toString();
  return other ?? n.toString();
}

/// Правило, которое нужно задать языку сверх встроенных в slang. `null` — хватает встроенного (ru, en).
PluralResolver? cardinalPluralResolverFor(AppLocale locale) => switch (locale) {
  AppLocale.be || AppLocale.uk => _slavicCardinal,
  AppLocale.hy => _armenianCardinal,
  AppLocale.az ||
  AppLocale.ka ||
  AppLocale.kk ||
  AppLocale.ky ||
  AppLocale.tg ||
  AppLocale.tk ||
  AppLocale.uz => _oneOtherCardinal,
  AppLocale.ru || AppLocale.en => null,
};

extension AppLocaleTranslations on AppLocale {
  /// Тексты языка с нашими правилами множественного числа. Вместо `build()`.
  Future<Translations> buildTranslations() => build(cardinalResolver: cardinalPluralResolverFor(this));
}
