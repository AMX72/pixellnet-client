import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// PIXELLNET onboarding — 3 экрана (Sprint 5, design consilium 2026-07-08):
/// 1. **Привет!** — большой лого + слоган
/// 2. **Как это работает** — 2-3 иконки-шага с текстом
/// 3. **Готово!** — «Нажми большую кнопку — и всё заработает» + [Понятно]
///
/// От лингвиста (agent-linguist-copywriter): простой русский B1, ты-обращение,
/// глаголы вместо существительных, никаких VPN/TUN/proxy.
class IntroPage extends HookConsumerWidget with PresLogger {
  const IntroPage({super.key});

  static bool locationInfoLoaded = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pageController = usePageController();
    final currentPage = useState<int>(0);
    final isStarting = useState(false);

    // Auto-detect region в фоне при первом рендере — не блокирует UI.
    if (!locationInfoLoaded) {
      autoSelectRegion(ref).then((_) => loggy.debug("Auto Region selection finished"));
      locationInfoLoaded = true;
    }

    Future<void> finishIntro() async {
      if (isStarting.value) return;
      isStarting.value = true;
      if (!ref.read(analyticsControllerProvider).requireValue) {
        try {
          await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
        } catch (e, s) {
          loggy.error("could not disable analytics", e, s);
        }
      }
      await ref.read(Preferences.introCompleted.notifier).update(true);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: pageController,
                onPageChanged: (i) => currentPage.value = i,
                children: const [
                  _WelcomeStep(),
                  _HowItWorksStep(),
                  _ReadyStep(),
                ],
              ),
            ),
            // Индикатор шагов
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final active = i == currentPage.value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: active ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            // Кнопки Назад / Далее / Готово
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (currentPage.value > 0)
                    TextButton(
                      onPressed: () => pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      ),
                      child: const Text('Назад'),
                    )
                  else
                    const SizedBox(width: 64),
                  const Spacer(),
                  FilledButton(
                    onPressed: currentPage.value < 2
                        ? () => pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            )
                        : finishIntro,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isStarting.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(currentPage.value < 2 ? 'Далее' : 'Понятно'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> autoSelectRegion(WidgetRef ref) async {
    try {
      final countryCode = RegionDetector.detect();
      final regionLocale = _getRegionLocale(countryCode);
      await ref.read(ConfigOptions.region.notifier).update(regionLocale.region);
      await ref.watch(ConfigOptions.directDnsAddress.notifier).reset();
      await ref.read(localePreferencesProvider.notifier).changeLocale(regionLocale.locale);
      return;
    } catch (e) {
      loggy.warning('Could not detect region from timezone', e);
    }

    try {
      final client = DioHttpClient(
        timeout: const Duration(seconds: 2),
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0",
        debug: true,
      );
      final response = await client.get<Map<String, dynamic>>('https://api.ip.sb/geoip/');
      if (response.statusCode == 200) {
        final jsonData = response.data!;
        final regionLocale = _getRegionLocale(jsonData['country_code']?.toString() ?? "");
        await ref.read(ConfigOptions.region.notifier).update(regionLocale.region);
        await ref.read(localePreferencesProvider.notifier).changeLocale(regionLocale.locale);
      }
    } catch (e) {
      loggy.warning('Could not detect region from IP', e);
    }
  }

  RegionLocale _getRegionLocale(String country) {
    switch (country.toUpperCase()) {
      case "IR":
        return RegionLocale(Region.ir, AppLocale.fa);
      case "CN":
        return RegionLocale(Region.cn, AppLocale.zhCn);
      case "RU":
        return RegionLocale(Region.ru, AppLocale.ru);
      case "AF":
        return RegionLocale(Region.af, AppLocale.fa);
      case "BR":
        return RegionLocale(Region.br, AppLocale.ptBr);
      case "TR":
        return RegionLocale(Region.tr, AppLocale.tr);
      default:
        return RegionLocale(Region.other, AppLocale.en);
    }
  }
}

/// Экран 1: Привет + слоган + мелкие ссылки на terms/license.
class _WelcomeStep extends HookConsumerWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Assets.images.logo.svg(width: 140, height: 140),
          const Gap(32),
          Text(
            'Привет!',
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Gap(16),
          Text(
            'PIXELLNET открывает сайты, которые не работают',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(24),
          // Terms/license — мелкий текст (по правилу legal — должно быть)
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Продолжая, ты соглашаешься с '),
                TextSpan(
                  text: 'условиями',
                  style: TextStyle(color: theme.colorScheme.primary),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl)),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Экран 2: Как это работает — 3 шага.
class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Как это работает',
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Gap(32),
          _Step(icon: Icons.vpn_key_outlined, title: 'Вставь ключ', text: 'Получил ключ после оплаты — скопируй и вставь'),
          const Gap(24),
          _Step(icon: Icons.power_settings_new_rounded, title: 'Нажми на кнопку', text: 'Большая круглая кнопка на главной — включает защиту'),
          const Gap(24),
          _Step(icon: Icons.language_rounded, title: 'Пользуйся', text: 'Открывай нужные сайты как раньше'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer, size: 24),
        ),
        const Gap(16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Gap(4),
              Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Экран 3: Готово!
class _ReadyStep extends StatelessWidget {
  const _ReadyStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 56, color: theme.colorScheme.onPrimaryContainer),
          ),
          const Gap(32),
          Text(
            'Готово!',
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Gap(16),
          Text(
            'Нажми большую кнопку — и всё заработает',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class RegionLocale {
  final Region region;
  final AppLocale locale;
  RegionLocale(this.region, this.locale);
}

class RegionDetector {
  static String detect() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inMinutes;
    final tz = now.timeZoneName.toLowerCase().trim();

    if (offset == 210) return 'IR';
    if (offset == 270) {
      final (_, country) = _parseLocale();
      return country == 'IR' ? 'IR' : 'AF';
    }
    final fromName = _fromTzName(tz, offset);
    if (fromName != null) return fromName;
    final candidates = _candidatesForOffset(offset);
    if (candidates.isEmpty) return 'US';
    return _resolveByLocale(candidates);
  }

  static String? _fromTzName(String tz, int offset) {
    if (tz.contains('/')) {
      final city = tz.split('/').last.replaceAll(' ', '_');
      final r = _ianaCities[city];
      if (r != null) return r;
    }
    if (tz == 'irst' || tz == 'irdt' || tz.contains('iran')) return 'IR';
    if (tz == 'aft' || tz.contains('afghanistan')) return 'AF';
    if (tz == 'trt' || tz.contains('turkey') || tz.contains('istanbul')) return 'TR';
    if (tz.contains('china') || tz.contains('beijing')) return 'CN';
    if (tz == 'cst' && offset == 480) return 'CN';
    if (_matchesRussiaTz(tz)) return 'RU';
    if (_matchesBrazilTz(tz)) return 'BR';
    return null;
  }

  static bool _matchesRussiaTz(String tz) {
    if (tz.contains('russia') || tz.contains('moscow')) return true;
    const abbrs = {'msk', 'yekt', 'omst', 'krat', 'irkt', 'yakt', 'vlat', 'magt', 'pett', 'sakt', 'sret'};
    if (abbrs.contains(tz)) return true;
    const winKeys = ['ekaterinburg', 'kaliningrad', 'yakutsk', 'vladivostok', 'magadan', 'sakhalin', 'kamchatka', 'astrakhan', 'saratov', 'volgograd', 'altai', 'tomsk', 'transbaikal', 'n. central asia', 'north asia'];
    return winKeys.any(tz.contains);
  }

  static bool _matchesBrazilTz(String tz) {
    if (tz == 'brt' || tz == 'brst') return true;
    if (tz.contains('brazil') || tz.contains('brasilia')) return true;
    const winKeys = ['e. south america', 'central brazilian', 'tocantins', 'bahia'];
    return winKeys.any(tz.contains);
  }

  static Set<String> _candidatesForOffset(int offset) {
    final c = <String>{};
    if (offset == 180) c.add('TR');
    if (offset == 480) c.add('CN');
    if (_ruOffsets.contains(offset)) c.add('RU');
    if (_brOffsets.contains(offset)) c.add('BR');
    return c;
  }

  static const _ruOffsets = {120, 180, 240, 300, 360, 420, 480, 540, 600, 660, 720};
  static const _brOffsets = {-120, -180, -240, -300};

  static String _resolveByLocale(Set<String> candidates) {
    final (lang, country) = _parseLocale();
    if (country != null && candidates.contains(country)) return country;
    final regionFromLang = _langToRegion[lang];
    if (regionFromLang != null && candidates.contains(regionFromLang)) return regionFromLang;
    return 'US';
  }

  static (String, String?) _parseLocale() {
    try {
      final parts = Platform.localeName.split(RegExp(r'[_\-.]'));
      final lang = parts.first.toLowerCase();
      String? country;
      for (final p in parts.skip(1)) {
        if (p.length == 2) {
          country = p.toUpperCase();
          break;
        }
      }
      return (lang, country);
    } catch (_) {
      return ('en', null);
    }
  }

  static const _langToRegion = <String, String>{'fa': 'IR', 'ps': 'AF', 'tr': 'TR', 'zh': 'CN', 'ru': 'RU', 'pt': 'BR'};

  static const _ianaCities = <String, String>{
    'tehran': 'IR', 'kabul': 'AF', 'istanbul': 'TR', 'shanghai': 'CN', 'chongqing': 'CN', 'urumqi': 'CN', 'harbin': 'CN',
    'moscow': 'RU', 'kaliningrad': 'RU', 'samara': 'RU', 'yekaterinburg': 'RU', 'omsk': 'RU', 'novosibirsk': 'RU',
    'barnaul': 'RU', 'tomsk': 'RU', 'krasnoyarsk': 'RU', 'irkutsk': 'RU', 'chita': 'RU', 'yakutsk': 'RU',
    'vladivostok': 'RU', 'magadan': 'RU', 'sakhalin': 'RU', 'kamchatka': 'RU', 'anadyr': 'RU', 'volgograd': 'RU',
    'saratov': 'RU', 'astrakhan': 'RU', 'sao_paulo': 'BR', 'fortaleza': 'BR', 'recife': 'BR', 'manaus': 'BR',
    'belem': 'BR', 'cuiaba': 'BR', 'bahia': 'BR', 'rio_branco': 'BR', 'noronha': 'BR', 'porto_velho': 'BR',
    'campo_grande': 'BR',
  };
}
