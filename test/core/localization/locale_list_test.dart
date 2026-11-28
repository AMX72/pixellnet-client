import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 28.11, T-026: решение владельца — 12 языков: русский (основной), английский и языки СНГ.
/// Убраны ar, es, fa, fr, id, pt-BR, tr, zh-CN, zh-TW.
const _codes = {'ru', 'en', 'kk', 'ky', 'uk', 'be', 'az', 'hy', 'ka', 'tg', 'tk', 'uz'};

/// Значения, которые были в настройках до 0.1.106 у людей с убранными языками (имена `AppLocale` и теги).
const _removedSaved = [
  'ar',
  'es',
  'fa',
  'fr',
  'id',
  'tr',
  'ptBr',
  'zhCn',
  'zhTw',
  'zh',
  'pt-BR',
  'pt_BR',
  'zh-CN',
  'zh_TW',
  'xx',
  '',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('12 languages', () {
    test('AppLocale has exactly 12 languages', () {
      expect(AppLocale.values.map((l) => l.languageCode).toSet(), _codes);
      expect(AppLocale.values.length, 12);
      expect(AppLocale.values.every((l) => l.countryCode == null && l.scriptCode == null), isTrue);
    });

    test('translation files: exactly 12', () {
      final files = Directory('assets/translations')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.i18n.json'))
          .map((n) => n.replaceAll('.i18n.json', ''))
          .toSet();
      expect(files, _codes);
    });

    test('Android notification strings: values-<lang> only for the 11 languages besides English', () {
      final dirs = Directory('android/app/src/main/res')
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .where((n) => n.startsWith('values-') && n != 'values-night' && n != 'values-night-v31' && n != 'values-v31')
          .map((n) => n.substring('values-'.length))
          .toSet();
      expect(dirs, _codes.difference({'en'}));
      for (final d in dirs) {
        final files = Directory('android/app/src/main/res/values-$d').listSync().map((f) => f.uri.pathSegments.last);
        expect(files.toList(), ['strings.xml'], reason: 'values-$d');
      }
    });

    test('list order: Russian, English, then CIS languages by their Russian names', () {
      expect(kAppLocalesInListOrder.length, 12);
      expect(kAppLocalesInListOrder.toSet(), AppLocale.values.toSet());
      expect(kAppLocalesInListOrder.map((l) => l.languageCode).toList(), [
        'ru', 'en', // основной и английский
        'az', 'hy', 'be', 'ka', 'kk', 'ky', 'tg', 'tk', 'uz', 'uk', // азербайджанский ... украинский
      ]);
    });

    test('every language has its own name in the list', () {
      final names = AppLocale.values.map((l) => l.localeName).toList();
      expect(names, isNot(contains('Unknown')));
      expect(names.toSet().length, 12);
      expect(AppLocale.ru.localeName, 'Русский');
      expect(AppLocale.en.localeName, 'English');
    });
  });

  group('saved language', () {
    test('saved language among the 12 opens as saved', () {
      for (final l in AppLocale.values) {
        expect(resolveAppLocale(l.name), l);
      }
    });

    test('saved removed language opens English', () {
      for (final saved in _removedSaved) {
        expect(resolveAppLocale(saved), AppLocale.en, reason: 'saved "$saved"');
      }
    });

    test('nothing saved: device language among the 12, otherwise English', () {
      for (final l in AppLocale.values) {
        expect(resolveAppLocale(null, device: Locale(l.languageCode)), l, reason: l.languageCode);
        expect(resolveAppLocale(null, device: Locale(l.languageCode, 'XX')), l, reason: '${l.languageCode}_XX');
      }
      expect(resolveAppLocale(null, device: const Locale('ru', 'RU')), AppLocale.ru);
      expect(resolveAppLocale(null, device: const Locale('uz', 'UZ')), AppLocale.uz);
      expect(
        resolveAppLocale(
          null,
          device: const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
        ),
        AppLocale.uz,
      );
      for (final lang in ['ar', 'es', 'fa', 'fr', 'id', 'pt', 'tr', 'zh', 'de', 'ja', 'hi', 'ps']) {
        expect(resolveAppLocale(null, device: Locale(lang)), AppLocale.en, reason: lang);
      }
      expect(resolveAppLocale(null, device: const Locale('pt', 'BR')), AppLocale.en);
      expect(
        resolveAppLocale(
          null,
          device: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        ),
        AppLocale.en,
      );
    });

    test('nothing saved: the platform language is used', () {
      final binding = TestWidgetsFlutterBinding.instance;
      binding.platformDispatcher.localeTestValue = const Locale('kk', 'KZ');
      addTearDown(binding.platformDispatcher.clearLocaleTestValue);
      expect(resolveAppLocale(null), AppLocale.kk);
      binding.platformDispatcher.localeTestValue = const Locale('es', 'ES');
      expect(resolveAppLocale(null), AppLocale.en);
    });

    Future<ProviderContainer> containerWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      return container;
    }

    test('saved removed language is rewritten to en', () async {
      for (final saved in ['ar', 'es', 'fa', 'fr', 'id', 'ptBr', 'tr', 'zhCn', 'zhTw', 'zh']) {
        final container = await containerWith({'locale': saved});
        expect(container.read(localePreferencesProvider), AppLocale.en, reason: saved);
        await Future<void>.delayed(Duration.zero);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('locale'), 'en', reason: 'saved "$saved" must be replaced by en');
      }
    });

    test('saved language among the 12 stays untouched', () async {
      for (final l in AppLocale.values) {
        final container = await containerWith({'locale': l.name});
        expect(container.read(localePreferencesProvider), l);
        await Future<void>.delayed(Duration.zero);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('locale'), l.name);
      }
    });

    test('nothing saved: nothing is written', () async {
      final container = await containerWith({});
      container.read(localePreferencesProvider);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('locale'), isFalse);
    });
  });
}
