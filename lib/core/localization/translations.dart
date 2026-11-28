import 'package:flutter/widgets.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/plural_rules.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:hiddify/gen/translations.g.dart';

part 'translations.g.dart';

@Riverpod(keepAlive: true)
Future<Translations> translations(Ref ref) async {
  return await ref.watch(localePreferencesProvider).buildTranslations();
}

/// Тексты текущего языка для кода, у которого есть `BuildContext`, но нет `ref`
/// (шторки и окна без Riverpod). Читает значение один раз: окно живёт недолго, язык при открытом окне не меняется.
extension TranslationsBuildContext on BuildContext {
  Translations get t => ProviderScope.containerOf(this, listen: false).read(translationsProvider).requireValue;
}
