import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// v0.1.27: страница «Ключи» унифицирована — под каждым ключом
/// сразу список каналов (серверов). Юзер видит всё на одном экране,
/// не нужно тапать в профиль → потом в proxies → потом выбирать.
class ProfilesPage extends HookConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final asyncProfiles = ref.watch(profilesNotifierProvider);

    ref.listen(hasAnyProfileProvider, (_, next) {
      if (next.value == false) {
        context.goNamed('home');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.profiles.title),
        actions: [
          IconButton(
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.update_rounded),
            tooltip: t.pages.profiles.updateSubscriptions,
          ),
          IconButton(
            onPressed: () => ref.read(dialogNotifierProvider.notifier).showSortProfiles(),
            icon: const Icon(Icons.sort_rounded),
            tooltip: t.common.sort,
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async => await ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
        label: Text(t.pages.profiles.add),
        icon: const Icon(Icons.add_rounded),
      ),
      body: asyncProfiles.when(
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
          children: [
            for (final profile in data) ...[
              ProfileTile(profile: profile),
              // Только для активного профиля показываем список каналов
              // (пока в MVP — один профиль это норма 99% юзеров).
              if (profile.active) ...[
                const Gap(16),
                _ChannelsSection(),
                const Gap(12),
              ] else
                const Gap(12),
            ],
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Text(t.presentShortError(error)),
      ),
    );
  }
}

/// Секция «Каналы» — список outbound-серверов активного профиля.
/// Тап на канал → переключение (changeProxy). Флаг + имя + пинг.
class _ChannelsSection extends ConsumerWidget {
  const _ChannelsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final proxies = ref.watch(proxiesOverviewNotifierProvider);

    return proxies.when(
      data: (group) {
        if (group == null || group.items.isEmpty) return const SizedBox.shrink();
        final selectedTag = group.selected;
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.public_rounded,
                        color: PixellnetBrand.mocha, size: 18),
                    const Gap(8),
                    Text('Каналы (${group.items.length})',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (int i = 0; i < group.items.length; i++) ...[
                _ChannelTile(
                  item: group.items[i],
                  selected: group.items[i].tag == selectedTag,
                  onTap: () => ref
                      .read(proxiesOverviewNotifierProvider.notifier)
                      .changeProxy(group.tag, group.items[i].tag),
                ),
                if (i < group.items.length - 1) const Divider(height: 1, indent: 60),
              ],
            ],
          ),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const Gap(12),
              Text('Ищем каналы…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: PixellnetBrand.textSecondary)),
            ],
          ),
        ),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Включи VPN — сможешь увидеть все каналы',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: PixellnetBrand.textSecondary),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final OutboundInfo item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delay = item.urlTestDelay;
    final quality = _quality(delay);
    final delayText = delay > 0 && delay < 65000 ? '$delay мс' : '—';
    final country = _countryName(item.ipinfo.countryCode);
    final name = item.tagDisplay.isNotEmpty ? item.tagDisplay : item.tag;
    final title = country.isNotEmpty ? '$country · $name' : name;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: PixellnetBrand.mocha.withValues(alpha: selected ? 0.35 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                selected ? Icons.check_rounded : Icons.public_rounded,
                color: PixellnetBrand.mochaOnDark,
                size: 16,
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      )),
                  Text(quality,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: PixellnetBrand.textSecondary)),
                ],
              ),
            ),
            Text(delayText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: PixellnetBrand.textSecondary,
                  fontFamily: 'Consolas',
                )),
          ],
        ),
      ),
    );
  }

  static String _quality(int delay) {
    if (delay <= 0 || delay >= 65000) return 'Проверяем связь…';
    if (delay < 200) return 'Быстрый';
    if (delay < 500) return 'Обычный';
    return 'Медленный';
  }

  static String _countryName(String code) {
    const map = {
      'DE': 'Германия', 'NL': 'Нидерланды', 'LT': 'Литва', 'FI': 'Финляндия',
      'FR': 'Франция', 'SE': 'Швеция', 'US': 'США', 'GB': 'Великобритания',
      'CH': 'Швейцария', 'AT': 'Австрия', 'PL': 'Польша', 'CZ': 'Чехия',
      'RU': 'Россия', 'UA': 'Украина', 'BY': 'Беларусь', 'KZ': 'Казахстан',
      'TR': 'Турция',
    };
    return map[code.toUpperCase()] ?? '';
  }
}
