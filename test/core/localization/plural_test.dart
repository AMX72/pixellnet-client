import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/plural_rules.dart';
import 'package:hiddify/gen/translations.g.dart';

/// 28.11, T-026: формы множественного числа на всех 12 языках.
/// В slang 4.8.1 нет правила для белорусского (be) и армянского и других (az, ka, kk, ky, tg, tk, uz);
/// встроенное правило украинского для 0 отдаёт форму `other` («0 дня»). Наши правила — `plural_rules.dart`.
///
/// Ожидаемый текст берётся из самого файла переводов (`ui.home.days(plural, param=n)`), а не вписан в тест:
/// переводчик может поправить слова, а проверяется выбор формы.
Map<String, dynamic> _daysForms(String lang) {
  final raw = File('assets/translations/$lang.i18n.json').readAsStringSync();
  final json = jsonDecode(raw.startsWith('﻿') ? raw.substring(1) : raw) as Map<String, dynamic>;
  return ((json['ui'] as Map<String, dynamic>)['home'] as Map<String, dynamic>)['days(plural, param=n)']
      as Map<String, dynamic>;
}

String _form(Map<String, dynamic> forms, String category, num n) =>
    (forms[category] as String? ?? forms['other'] as String).replaceAll(r'$n', '$n');

void main() {
  group('be, uk, ru: one / few / many (CLDR)', () {
    const cases = <(num, String)>[
      (0, 'many'),
      (1, 'one'),
      (2, 'few'),
      (3, 'few'),
      (4, 'few'),
      (5, 'many'),
      (9, 'many'),
      (10, 'many'),
      (11, 'many'),
      (12, 'many'),
      (14, 'many'),
      (20, 'many'),
      (21, 'one'),
      (22, 'few'),
      (25, 'many'),
      (101, 'one'),
      (111, 'many'),
      (112, 'many'),
      (1000, 'many'),
    ];
    for (final lang in ['ru', 'be', 'uk']) {
      test('days on $lang', () async {
        final locale = AppLocale.values.firstWhere((l) => l.languageCode == lang);
        final t = await locale.buildTranslations();
        final forms = _daysForms(lang);
        for (final (n, category) in cases) {
          expect(t.ui.home.days(n: n), _form(forms, category, n), reason: '$lang: n=$n must be "$category"');
        }
      });
    }

    test('few and many differ from one in be and uk (otherwise the test proves nothing)', () {
      for (final lang in ['be', 'uk']) {
        final forms = _daysForms(lang);
        expect({forms['one'], forms['few'], forms['many']}.length, 3, reason: lang);
      }
    });

    test('fractions use other', () async {
      for (final lang in ['be', 'uk']) {
        final locale = AppLocale.values.firstWhere((l) => l.languageCode == lang);
        final t = await locale.buildTranslations();
        expect(t.ui.home.days(n: 2.5), _form(_daysForms(lang), 'other', 2.5), reason: lang);
      }
    });
  });

  group('one / other languages', () {
    for (final lang in ['en', 'az', 'hy', 'ka', 'kk', 'ky', 'tg', 'tk', 'uz']) {
      test('days on $lang', () async {
        final locale = AppLocale.values.firstWhere((l) => l.languageCode == lang);
        final t = await locale.buildTranslations();
        final forms = _daysForms(lang);
        expect(t.ui.home.days(n: 1), _form(forms, 'one', 1), reason: '$lang: 1');
        expect(t.ui.home.days(n: 2), _form(forms, 'other', 2), reason: '$lang: 2');
        expect(t.ui.home.days(n: 5), _form(forms, 'other', 5), reason: '$lang: 5');
        expect(t.ui.home.days(n: 21), _form(forms, 'other', 21), reason: '$lang: 21');
      });
    }
  });

  test('every language has an explicit rule or relies on the built-in one (ru, en)', () {
    for (final l in AppLocale.values) {
      final custom = cardinalPluralResolverFor(l);
      if (l == AppLocale.ru || l == AppLocale.en) {
        expect(custom, isNull, reason: l.languageTag);
      } else {
        expect(
          custom,
          isNotNull,
          reason: '${l.languageTag}: no plural rule (slang would print a warning and use the fallback)',
        );
      }
    }
  });
}
