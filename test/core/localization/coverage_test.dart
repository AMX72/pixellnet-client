import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T-026, шаг 7: покрытие переводов. У каждого из 12 языков (Р-22) — все ключи английского файла, лишних нет,
/// пустых строк нет, подстановки (`$x`, `${x}`, `{x}`) те же, что в en. Запускается в CI перед сборкой.
const _langs = ['ru', 'en', 'kk', 'ky', 'uk', 'be', 'az', 'hy', 'ka', 'tg', 'tk', 'uz'];
const _cats = {'zero', 'one', 'two', 'few', 'many', 'other'};
final _ph = RegExp(r'\$\{(\w+)\}|\$(\w+)|\{(\w+)\}');

Map<String, dynamic> _load(String lang) {
  final raw = File('assets/translations/$lang.i18n.json').readAsStringSync();
  return jsonDecode(raw.startsWith('﻿') ? raw.substring(1) : raw) as Map<String, dynamic>;
}

/// Плоский список «ключ → значение». Узел множественного числа (все ключи — формы) — один ключ:
/// у языков разный набор форм (у ru есть few и many, у en — нет).
void _flat(Object? node, String path, Map<String, Object?> out) {
  if (node is Map<String, dynamic>) {
    final plural = path.contains('(plural') || (node.length >= 2 && node.keys.every(_cats.contains));
    if (plural) {
      out[path] = node;
      return;
    }
    node.forEach((k, v) => _flat(v, path.isEmpty ? k : '$path.$k', out));
  } else {
    out[path] = node;
  }
}

Set<String> _phs(String s) => _ph.allMatches(s).map((m) => m.group(1) ?? m.group(2) ?? m.group(3)!).toSet();

void main() {
  final en = <String, Object?>{};
  _flat(_load('en'), '', en);

  test('translation files: exactly 12 languages', () {
    final files = Directory('assets/translations')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.i18n.json'))
        .map((n) => n.split('.').first)
        .toSet();
    expect(files, _langs.toSet());
  });

  for (final lang in _langs) {
    test('coverage: $lang has every en key, no extra, no empty, same placeholders', () {
      final d = <String, Object?>{};
      _flat(_load(lang), '', d);
      final missing = en.keys.toSet().difference(d.keys.toSet());
      final extra = d.keys.toSet().difference(en.keys.toSet());
      expect(missing, isEmpty, reason: '$lang: нет перевода');
      expect(extra, isEmpty, reason: '$lang: лишние ключи');
      final empty = <String>[];
      final badPh = <String>[];
      en.forEach((k, ev) {
        final v = d[k];
        if (ev is String) {
          if (ev.trim().isNotEmpty && (v is! String || v.trim().isEmpty)) empty.add(k);
          if (v is String && !const SetEquality().equals(_phs(ev), _phs(v))) badPh.add(k);
        } else if (ev is List) {
          if (v is! List || v.length != ev.length || v.any((x) => x is! String || x.trim().isEmpty)) empty.add(k);
        } else if (ev is Map) {
          // Форма zero бывает пустой нарочно (как в оригинале en: при нуле подпись не показывается).
          if (v is! Map ||
              v.isEmpty ||
              v.entries.any((e) => e.value is! String || (e.key != 'zero' && (e.value as String).trim().isEmpty))) {
            empty.add(k);
          }
        }
      });
      expect(empty, isEmpty, reason: '$lang: пустые строки');
      expect(badPh, isEmpty, reason: '$lang: подстановки не как в en');
    });
  }
}

class SetEquality {
  const SetEquality();
  bool equals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
}
