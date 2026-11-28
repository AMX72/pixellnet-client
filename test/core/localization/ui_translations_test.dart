import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/gen/translations.g.dart';

/// T-026, шаг 4: тексты, вынесенные из кода (`ui.*`), есть и в ru, и в en; на остальных языках работает запасной (английский).
Map<String, dynamic> _ui(String lang) {
  final raw = File('assets/translations/$lang.i18n.json').readAsStringSync();
  final json = jsonDecode(raw.startsWith('﻿') ? raw.substring(1) : raw) as Map<String, dynamic>;
  return json['ui'] as Map<String, dynamic>;
}

void _collectKeys(Object? node, String path, Set<String> out) {
  // Множественные формы (`days(plural, param=n)`): у языков разный набор форм, сравниваем только сам ключ.
  if (node is Map<String, dynamic> && !path.contains('(plural')) {
    node.forEach((k, v) => _collectKeys(v, path.isEmpty ? k : '$path.$k', out));
  } else {
    out.add(path);
  }
}

void _collectStrings(Object? node, List<String> out) {
  if (node is Map<String, dynamic>) {
    node.values.forEach((v) => _collectStrings(v, out));
  } else if (node is List) {
    for (final v in node) {
      _collectStrings(v, out);
    }
  } else if (node is String) {
    out.add(node);
  }
}

void main() {
  test('ui: ru and en have the same keys', () {
    final ru = <String>{};
    final en = <String>{};
    _collectKeys(_ui('ru'), '', ru);
    _collectKeys(_ui('en'), '', en);
    expect(ru.difference(en), isEmpty, reason: 'keys only in ru');
    expect(en.difference(ru), isEmpty, reason: 'keys only in en');
    expect(ru.length, greaterThan(250));
  });

  test('ui: no Cyrillic in the English texts', () {
    final texts = <String>[];
    _collectStrings(_ui('en'), texts);
    final cyr = RegExp('[А-Яа-яЁё]');
    expect(texts.where(cyr.hasMatch), isEmpty);
  });

  test('ui: every language shows a text (fallback works)', () async {
    for (final l in AppLocale.values) {
      final t = await l.build();
      expect(t.ui.home.menu, isNotEmpty, reason: l.languageTag);
      expect(t.ui.common.close, isNotEmpty, reason: l.languageTag);
    }
  });

  test('ui: plural of days', () async {
    final ru = await AppLocale.ru.build();
    expect(ru.ui.home.days(n: 1), '1 день');
    expect(ru.ui.home.days(n: 2), '2 дня');
    expect(ru.ui.home.days(n: 5), '5 дней');
    expect(ru.ui.home.days(n: 11), '11 дней');
    expect(ru.ui.home.days(n: 21), '21 день');
    final en = await AppLocale.en.build();
    expect(en.ui.home.days(n: 1), '1 day');
    expect(en.ui.home.days(n: 5), '5 days');
    expect(ru.ui.home.monthsShort.length, 12);
    expect(en.ui.home.monthsShort.length, 12);
  });
}
