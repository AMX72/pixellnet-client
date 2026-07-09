import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// PIXELLNET — Главная (Sprint 2 + 4.2).
///
/// Два состояния:
/// 1. **Есть ключ** (`hasAnyProfile == true`): Connect button + quality indicator
/// 2. **Нет ключа** (пустое состояние): большая кнопка «Вставить ключ»
///    с объяснением куда взять ключ (Telegram/почта продавца)
///
/// Держим ≤3 focal элементов (Hick-Hyman). Один focal point на состояние.
class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final hasKey = ref.watch(hasAnyProfileProvider).valueOrNull ?? false;

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
            child: hasKey ? const _ConnectedBody() : _EmptyKeyBody(ref: ref),
          ),
        ),
      ),
    );
  }
}

/// Состояние 1 — ключ есть: Connect + quality indicator.
class _ConnectedBody extends StatelessWidget {
  const _ConnectedBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Spacer(),
        ConnectionButton(),
        Gap(24),
        ActiveProxyDelayIndicator(),
        Spacer(),
        // Bottom offset per UX Ergonomics agent (Fitts's Law: mouse rests near bottom).
        Gap(96),
      ],
    );
  }
}

/// Состояние 2 — ключа нет: empty state с кнопкой «Вставить ключ».
///
/// Layout per UX Ergonomics + Linguist:
/// - Icon 96×96 «vpn_key» на primaryContainer
/// - Title «Нужен ключ» headlineMedium
/// - Subtitle «Ключ приходит от продавца в Telegram или на почту»
/// - FilledButton 240×56 «Вставить ключ» — открывает showAddProfile
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
