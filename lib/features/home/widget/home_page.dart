import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/activation/notifier/trial_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// PIXELLNET — Главная (v0.0.24 — trial-aware).
///
/// Состояния:
/// 1. `hasKey && TrialActive (not expired, trial)` → Connect + badge TRIAL + ссылка «Оплатить»
/// 2. `hasKey && TrialActive (not expired, paid)` → Connect (чисто)
/// 3. `hasKey && expired trial` → Paywall модалка (Connect заблокирован)
/// 4. `!hasKey` → empty state «Вставить ключ» (резервный, не должно быть при нормальном flow)
class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final hasKey = ref.watch(hasAnyProfileProvider).valueOrNull ?? false;
    final trialState = ref.watch(trialStateProvider);

    // Показать paywall если trial истёк
    final showPaywall = trialState is TrialActive && trialState.showPaywall;

    // Пост-фрейм — показываем paywall диалог
    if (showPaywall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _showPaywallDialog(context);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Assets.images.logo.svg(height: 24),
            const Gap(8),
            Text(t.common.appTitle),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'),
            fit: BoxFit.cover,
            opacity: 0.06,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(theme.colorScheme.onSurface.withValues(alpha: .12), BlendMode.srcIn)
                : ColorFilter.mode(theme.colorScheme.onSurface.withValues(alpha: .5), BlendMode.srcATop),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: hasKey
                ? _ConnectedBody(trialState: trialState)
                : _EmptyKeyBody(ref: ref),
          ),
        ),
      ),
    );
  }

  void _showPaywallDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PaywallDialog(),
    );
  }
}

/// Состояние — ключ есть: Connect + опционально trial badge.
class _ConnectedBody extends StatelessWidget {
  const _ConnectedBody({required this.trialState});
  final TrialState trialState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTrial = trialState is TrialActive && (trialState as TrialActive).isTrial;
    final daysLeft = trialState is TrialActive ? (trialState as TrialActive).daysLeft : 0;

    return Column(
      children: [
        const Spacer(),
        const ConnectionButton(),
        const Gap(24),
        const ActiveProxyDelayIndicator(),
        const Spacer(),
        if (isTrial) ...[
          _TrialBadge(daysLeft: daysLeft, theme: theme),
          const Gap(8),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://pixellnet.com/pay'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Оплатить сейчас',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 13,
              ),
            ),
          ),
          const Gap(16),
        ] else
          const Gap(96),
      ],
    );
  }
}

class _TrialBadge extends StatelessWidget {
  const _TrialBadge({required this.daysLeft, required this.theme});
  final int daysLeft;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isUrgent = daysLeft <= 2;
    final color = isUrgent ? theme.colorScheme.error : const Color(0xFF00BCD4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        daysLeft > 0 ? 'TRIAL · осталось $daysLeft дн.' : 'TRIAL · последний день',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Paywall диалог — показывается когда trial истёк.
class _PaywallDialog extends StatelessWidget {
  const _PaywallDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Триал закончился'),
      content: const Text(
        'Продли подписку, чтобы продолжить пользоваться PIXELLNET.\n\n'
        'Базовый план — 299₽/мес',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            launchUrl(
              Uri.parse('https://pixellnet.com/pay'),
              mode: LaunchMode.externalApplication,
            );
          },
          child: const Text('Продлить за 299₽'),
        ),
      ],
    );
  }
}

/// Состояние — ключа нет (резервный empty state).
class _EmptyKeyBody extends StatelessWidget {
  const _EmptyKeyBody({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.vpn_key_rounded,
            size: 48,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const Gap(24),
        Text(
          'Нужен ключ',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Gap(8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Ключ приходит от продавца в Telegram или на почту.\nСкопируй и вставь сюда',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Gap(32),
        SizedBox(
          width: 240,
          height: 56,
          child: FilledButton.icon(
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Вставить ключ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const Spacer(),
        const Gap(96),
      ],
    );
  }
}
