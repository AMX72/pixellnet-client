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
      backgroundColor: PixellnetBrand.bgScaffold,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: isCompact ? 16 : 48),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: PixellnetBrand.accentBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.shield_outlined, size: 40, color: PixellnetBrand.accent),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Добро пожаловать',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: PixellnetBrand.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Стабильный доступ к зарубежным сервисам',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: PixellnetBrand.textSecondary,
                  height: 1.4,
                ),
              ),
              SizedBox(height: isCompact ? 32 : 56),

              _WelcomeRow(
                icon: Icons.bolt_outlined,
                title: 'Попробовать 7 дней бесплатно',
                subtitle: 'Без карты, без регистрации',
                onTap: _startTrial,
                primary: true,
              ),
              const SizedBox(height: 12),
              _WelcomeRow(
                icon: Icons.vpn_key_outlined,
                title: 'У меня уже есть ключ',
                subtitle: _clipboardHint != null
                    ? 'В буфере обмена найдена ссылка'
                    : 'Введите ключ или ссылку подписки',
                onTap: () => _enterKey(prefilledUrl: _clipboardHint),
                primary: false,
              ),

              const SizedBox(height: 32),

              Center(
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: PixellnetBrand.textMuted,
                    ),
                    children: const [
                      TextSpan(text: 'Есть вопросы? Напишите '),
                      TextSpan(
                        text: '@pixellnet_bot',
                        style: TextStyle(color: PixellnetBrand.accent, fontWeight: FontWeight.w500),
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

class _WelcomeRow extends StatelessWidget {
  const _WelcomeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? PixellnetBrand.accent : PixellnetBrand.bgSurface;
    final fg = primary ? const Color(0xFF131314) : PixellnetBrand.textPrimary;
    final sub = primary ? const Color(0xB3131314) : PixellnetBrand.textSecondary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: fg),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: sub,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_outlined, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
