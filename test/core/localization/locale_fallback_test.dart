import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/fallback_localizations.dart';
import 'package:hiddify/gen/translations.g.dart';

/// T-026, шаг 5: на каждом из языков приложения экран с AppBar и нижним окном строится без ошибок.
/// Для таджикского (tg) и туркменского (tk) без запасных делегатов Material-виджеты падают
/// («No MaterialLocalizations found»): у Flutter для них нет стандартных текстов.
void main() {
  for (final appLocale in AppLocale.values) {
    testWidgets('Material widgets build on locale ${appLocale.languageTag}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: appLocale.flutterLocale,
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            appBar: AppBar(title: const Text('x')),
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showModalBottomSheet<void>(context: ctx, builder: (c) => const Text('sheet')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('sheet'), findsOneWidget);
    });
  }
}
