import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/trial/auto_trial_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefWelcomeShown = 'pixellnet.welcome.shown';

/// Возвращает true если нужно показать welcome (fresh install без выбора).
/// После первого выбора юзер больше не увидит welcome.
final showWelcomeProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(_kPrefWelcomeShown) ?? false);
});

Future<void> _markWelcomeShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kPrefWelcomeShown, true);
}

/// v0.1.49: экран первого запуска — юзер выбирает trial или ввод ключа.
/// Показывается до `autoTrialProvider` — не автозапускать trial,
/// пока юзер сам не согласился.
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  String? _clipboardHint;
  bool _clipboardChecked = false;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted) return;
      // Определяем: похоже ли на sub URL / activation key
      final isUrl = text.startsWith('http://') || text.startsWith('https://') ||
          text.startsWith('vless://') || text.startsWith('vmess://') ||
          text.startsWith('trojan://') || text.startsWith('pixellnet://') ||
          text.startsWith('hiddify://');
      final isKey = RegExp(r'^PXN[-_][A-Z0-9]{4,6}[-_][A-Z0-9]{4,6}$', caseSensitive: false).hasMatch(text);
      setState(() {
        _clipboardHint = (isUrl || isKey) ? text : null;
        _clipboardChecked = true;
      });
    } catch (_) {
      if (mounted) setState(() => _clipboardChecked = true);
    }
  }

  Future<void> _startTrial() async {
    await _markWelcomeShown();
    if (!mounted) return;
    ref.invalidate(showWelcomeProvider);
    ref.invalidate(autoTrialProvider);
  }

  Future<void> _enterKey({String? prefilledUrl}) async {
    await _markWelcomeShown();
    if (!mounted) return;
    ref.invalidate(showWelcomeProvider);
    // AddProfileModal умеет принять url через параметр
    await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: prefilledUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isCompact = size.height < 700;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: isCompact ? 8 : 24),
              // Icon + brand
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: PixellnetBrand.mocha.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.shield_moon_rounded, size: 44, color: PixellnetBrand.mocha),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Добро пожаловать',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Стабильный доступ к зарубежным сервисам.\nВыберите как начать:',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              SizedBox(height: isCompact ? 24 : 40),

              // Card 1 — Trial
              _WelcomeCard(
                icon: Icons.bolt_rounded,
                iconColor: PixellnetBrand.olive,
                iconBg: PixellnetBrand.olive.withValues(alpha: 0.16),
                title: 'Попробовать 7 дней бесплатно',
                subtitle: 'Без карты, без регистрации. Заработает через 1 секунду.',
                cta: 'Начать',
                onTap: _startTrial,
              ),
              const SizedBox(height: 12),

              // Card 2 — Enter key
              _WelcomeCard(
                icon: Icons.vpn_key_rounded,
                iconColor: PixellnetBrand.mocha,
                iconBg: PixellnetBrand.mocha.withValues(alpha: 0.14),
                title: 'У меня уже есть ключ',
                subtitle: _clipboardHint != null
                    ? 'В буфере обмена найдена ссылка — использовать её?'
                    : 'Введите ключ или ссылку подписки от друга/поддержки',
                cta: _clipboardHint != null ? 'Вставить из буфера' : 'Ввести',
                onTap: () => _enterKey(prefilledUrl: _clipboardHint),
              ),

              const SizedBox(height: 24),

              // Hint снизу
              Center(
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    children: [
                      const TextSpan(text: 'Есть вопросы? Напишите '),
                      TextSpan(
                        text: '@pixellnet_bot',
                        style: TextStyle(color: PixellnetBrand.olive, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          cta,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 16, color: iconColor),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
