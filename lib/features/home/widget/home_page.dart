import 'dart:async';
import 'dart:convert';

import 'package:dartx/dartx.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/home/widget/ping_graph.dart';
import 'package:hiddify/features/profile/notifier/auto_profile_refresh_notifier.dart';
import 'package:hiddify/features/updater/auto_update_notifier.dart';
import 'package:hiddify/features/updater/changelog_sheet.dart';
import 'package:hiddify/features/updater/update_dialog.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/features/connection/notifier/vpn_permission_recovery.dart';
import 'package:hiddify/features/onboarding/welcome_page.dart';
import 'package:hiddify/features/trial/auto_trial_provider.dart';
import 'package:hiddify/features/trial/trial_service.dart';
import 'package:hiddify/features/trial/widget/trial_expired_page.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final showWelcome = ref.watch(showWelcomeProvider).value ?? false;
    final hasProfile = ref.watch(hasAnyProfileProvider).value ?? false;
    final autoTrial = showWelcome ? const AsyncValue<TrialInfo?>.data(null) : ref.watch(autoTrialProvider);
    ref.watch(autoUpdateStateProvider);
    // ignore: unused_local_variable
    final profileRefreshState = ref.watch(autoProfileRefreshProvider);
    ref.listen<AutoProfileRefreshState>(autoProfileRefreshProvider, (prev, next) {
      if (next.pendingAsk && !(prev?.pendingAsk ?? false)) {
        _showProfileRefreshAskSheet(context, ref);
      }
    });
    final vpnPermState = ref.watch(vpnPermissionRecoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Assets.images.logo.svg(height: 20),
            const Gap(10),
            Text(t.common.appTitle),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_outlined),
            tooltip: 'Меню',
            onPressed: () => _showOverflowSheet(context, ref),
          ),
          const Gap(4),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: _UpdateAvailableBanner()),
                  const SliverToBoxAdapter(child: _PostUpdateBanner()),
                  const SliverToBoxAdapter(child: _StatusHero()),
                  const SliverToBoxAdapter(child: _ConnectionSection()),
                  const SliverToBoxAdapter(child: _TrafficSection()),
                  const SliverToBoxAdapter(child: _SubscriptionSection()),
                  const SliverToBoxAdapter(child: _SettingsSection()),
                  const SliverToBoxAdapter(child: _FooterRow()),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
          if (showWelcome && !hasProfile)
            const Positioned.fill(child: WelcomePage()),
          if (autoTrial.isLoading)
            Container(
              color: theme.scaffoldBackgroundColor.withValues(alpha: 0.9),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const Gap(20),
                  Text('Готовим пробный период',
                      style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                  const Gap(6),
                  Text('Одна секунда',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          if (autoTrial.hasError)
            if (autoTrial.error is TrialException && (autoTrial.error as TrialException).isExpired)
              const TrialExpiredPage()
            else
              Container(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_outlined, size: 44, color: theme.colorScheme.error),
                    const Gap(16),
                    Text('Не получилось создать пробный доступ',
                        style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                    const Gap(6),
                    Text(
                      autoTrial.error is TrialException
                          ? (autoTrial.error as TrialException).message
                          : 'Проверьте интернет и попробуйте снова',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const Gap(20),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(autoTrialProvider),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
          if (vpnPermState != VpnPermissionState.ok)
            Positioned(
              left: 16,
              right: 16,
              top: 8,
              child: _VpnPermissionBanner(state: vpnPermState),
            ),
        ],
      ),
    );
  }

  static void _showOverflowSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.show_chart_outlined, size: 20),
                title: const Text('Диагностика'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // TODO: route to diagnostics screen
                },
              ),
              const Divider(height: 0.5, indent: 20),
              ListTile(
                leading: const Icon(Icons.description_outlined, size: 20),
                title: const Text('Логи'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // TODO: route to logs
                },
              ),
              const Divider(height: 0.5, indent: 20),
              ListTile(
                leading: const Icon(Icons.info_outline, size: 20),
                title: const Text('О программе'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // TODO: show about sheet
                },
              ),
              const Gap(8),
            ],
          ),
        );
      },
    );
  }

  /// v0.1.38: bottom sheet «Обновить прокси-каналы?» для mode=ask.
  static void _showProfileRefreshAskSheet(
      BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_sync_rounded, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Обновить список каналов?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Появились новые каналы. Обновить сейчас?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                ref
                    .read(autoProfileRefreshProvider.notifier)
                    .confirmRefresh();
              },
              child: const Text('Обновить'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(autoProfileRefreshProvider.notifier).dismissAsk();
              },
              child: const Text('Не сейчас'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Info-strip с live-скоростью: `Gandalf · 45ms · vless · ↑12KB/s ↓340KB/s`.
///
/// Дизайн (app-designer bimodal spec): 11sp Mono muted alpha 55% — домохозяйка
/// не замечает (как EXIF), IT-юзер сразу видит нужное. Обновляется каждую
/// секунду через Timer.periodic, скорость вычисляется как delta upload/
/// download от предыдущего тика. Long-press копирует в буфер обмена.
class _InfoStrip extends ConsumerStatefulWidget {
  const _InfoStrip();

  @override
  ConsumerState<_InfoStrip> createState() => _InfoStripState();
}

class _InfoStripState extends ConsumerState<_InfoStrip> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    if (connection is! Connected) return const SizedBox.shrink();

    final active = ref.watch(activeProxyNotifierProvider).valueOrNull;
    if (active == null) return const SizedBox.shrink();

    // v0.1.25: скорости из SystemInfo.uplink/downlink (bytes/sec от sing-box
    // core через gRPC). Раньше вычислял delta от active.upload вручную —
    // не работало потому что active.upload = cumulative от group-outbound,
    // не активной сессии. Восстановлено из baseline v0.1.0 stats-модуль.
    final stats = ref.watch(statsNotifierProvider).valueOrNull;
    final upSpeed = (stats?.uplink.toInt() ?? 0).toDouble();
    final downSpeed = (stats?.downlink.toInt() ?? 0).toDouble();

    final delay = active.urlTestDelay;
    final delayText = delay > 0 && delay < 65000 ? '${delay}ms' : '—';
    final name = active.tagDisplay.isNotEmpty
        ? active.tagDisplay
        : (active.tag.isNotEmpty ? active.tag : '—');
    final protocol = active.type.isNotEmpty ? active.type : '';
    final speedPart = '↑${_formatSpeed(upSpeed)} ↓${_formatSpeed(downSpeed)}';
    final parts = [
      name,
      delayText,
      if (protocol.isNotEmpty) protocol,
      speedPart,
    ];
    final line = parts.join(' · ');

    return GestureDetector(
      // Тап → session sheet с деталями (v0.1.22)
      onTap: () => _showSessionSheet(context, active, upSpeed, downSpeed),
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: line));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скопировано')),
        );
      },
      child: Text(
        line,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 11,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toInt()}B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(0)}KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  }

  void _showSessionSheet(BuildContext context, OutboundInfo active, double up, double down) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final rows = <(String, String)>[
          ('Канал', active.tagDisplay.isNotEmpty ? active.tagDisplay : active.tag),
          ('Страна', active.ipinfo.countryCode.isNotEmpty ? active.ipinfo.countryCode : '—'),
          ('IP выходной',
              active.ipinfo.ip.isNotEmpty ? active.ipinfo.ip : '—'),
          ('Провайдер (ASN)',
              active.ipinfo.org.isNotEmpty ? active.ipinfo.org : '—'),
          ('Протокол', active.type.isNotEmpty ? active.type : '—'),
          ('Задержка',
              active.urlTestDelay > 0 && active.urlTestDelay < 65000
                  ? '${active.urlTestDelay} мс'
                  : '—'),
          ('Скорость сейчас',
              '↑${_formatSpeed(up)}  ↓${_formatSpeed(down)}'),
          ('Всего за сессию',
              '↑${_bytes(active.upload.toInt())}  ↓${_bytes(active.download.toInt())}'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Сессия',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Gap(4),
                Text('Технические детали текущего соединения',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Gap(16),
                // v0.1.29: live-график скорости за 60 секунд
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.download_rounded,
                              size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const Gap(4),
                          Text('Скачивание за минуту',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      const PingGraph(metric: PingMetric.downSpeed, height: 60),
                      const Gap(8),
                      Row(
                        children: [
                          Icon(Icons.upload_rounded,
                              size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const Gap(4),
                          Text('Загрузка за минуту',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      const PingGraph(metric: PingMetric.upSpeed, height: 60),
                    ],
                  ),
                ),
                const Gap(16),
                for (final r in rows) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(r.$1,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        flex: 7,
                        child: Text(r.$2,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Consolas')),
                      ),
                    ],
                  ),
                  const Gap(10),
                ],
                const Gap(8),
                FilledButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Скопировать для поддержки'),
                  onPressed: () async {
                    final text = rows.map((r) => '${r.$1}: ${r.$2}').join('\n');
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _bytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// v5 Dashboard sections (Material 3 Dark / AI Studio aesthetic).
// Table-row layout, hairline dividers, Google Sans Text + mono values.
// ═══════════════════════════════════════════════════════════════════════════

const double _kRowPadH = 20;
const double _kSectionGap = 28;

Widget _sectionHeader(BuildContext context, String title) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(_kRowPadH, _kSectionGap, _kRowPadH, 10),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    ),
  );
}

Widget _hairline(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.only(left: _kRowPadH),
    child: Divider(
      height: 0.5,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    this.value,
    this.valueWidget,
    this.mono = false,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool mono;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: _kRowPadH, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (valueWidget != null)
              valueWidget!
            else if (value != null)
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: mono ? 13 : 14,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: mono ? 'JetBrainsMono' : null,
                    fontFamilyFallback: mono ? const ['Consolas', 'monospace'] : null,
                    fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
                  ),
                ),
              ),
            if (trailing != null) ...[
              const Gap(6),
              trailing!,
            ] else if (onTap != null) ...[
              const Gap(6),
              Icon(Icons.chevron_right_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hero секция сверху: dot + статус + sublabel + pill-кнопка.
class _StatusHero extends ConsumerWidget {
  const _StatusHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final conn = ref.watch(connectionNotifierProvider).valueOrNull;
    final active = ref.watch(activeProxyNotifierProvider).valueOrNull;

    // 4 состояния.
    Color dotColor;
    String statusTitle;
    String subtitle;
    String buttonLabel;
    bool buttonFilled;
    bool animateDot = false;

    if (conn is Connected) {
      dotColor = PixellnetBrand.success;
      statusTitle = 'Подключено';
      final name = active?.tagDisplay.isNotEmpty == true
          ? active!.tagDisplay
          : (active?.tag ?? '—');
      final delay = active?.urlTestDelay ?? 0;
      final delayPart = delay > 0 && delay < 65000 ? ' · $delay мс' : '';
      subtitle = '$name$delayPart';
      buttonLabel = 'Отключить';
      buttonFilled = false;
    } else if (conn is Connecting) {
      dotColor = PixellnetBrand.warning;
      statusTitle = 'Подключение…';
      subtitle = 'Устанавливаем соединение';
      buttonLabel = 'Отмена';
      buttonFilled = false;
      animateDot = true;
    } else {
      dotColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
      statusTitle = 'Не подключено';
      subtitle = 'Нажмите чтобы подключиться';
      buttonLabel = 'Подключить';
      buttonFilled = true;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kRowPadH, 24, _kRowPadH, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StatusDot(color: dotColor, animate: animateDot),
              const Gap(10),
              Expanded(
                child: Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const Gap(4),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Gap(20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: buttonFilled
                ? FilledButton(
                    onPressed: () =>
                        ref.read(connectionNotifierProvider.notifier).toggleConnection(),
                    child: Text(buttonLabel),
                  )
                : OutlinedButton(
                    onPressed: () =>
                        ref.read(connectionNotifierProvider.notifier).toggleConnection(),
                    child: Text(buttonLabel),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, this.animate = false});
  final Color color;
  final bool animate;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.animate) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.animate
          ? Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl)
          : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _ConnectionSection extends ConsumerWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final serverName = active?.tagDisplay.isNotEmpty == true
        ? active!.tagDisplay
        : (active?.tag ?? '—');
    final delay = active?.urlTestDelay ?? 0;
    final delayPart = delay > 0 && delay < 65000 ? ' · $delay мс' : '';
    final protocol = active?.type.isNotEmpty == true ? active!.type : 'Авто';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, 'Соединение'),
        _hairline(context),
        _Row(label: 'Сервер', value: '$serverName$delayPart', mono: true, onTap: () {}),
        _hairline(context),
        _Row(label: 'Протокол', value: protocol, onTap: () {}),
        _hairline(context),
        _Row(label: 'Режим', value: 'VPN (TUN)', onTap: () {}),
      ],
    );
  }
}

class _TrafficSection extends ConsumerWidget {
  const _TrafficSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionNotifierProvider).valueOrNull;
    if (conn is! Connected) return const SizedBox.shrink();

    final active = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final stats = ref.watch(statsNotifierProvider).valueOrNull;
    final upSpeed = (stats?.uplink.toInt() ?? 0).toDouble();
    final downSpeed = (stats?.downlink.toInt() ?? 0).toDouble();
    final totalUp = active?.upload.toInt() ?? 0;
    final totalDown = active?.download.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, 'Трафик'),
        _hairline(context),
        _Row(
          label: 'Сегодня',
          value: '↓ ${_bytesCompact(totalDown)}   ↑ ${_bytesCompact(totalUp)}',
          mono: true,
        ),
        _hairline(context),
        _Row(
          label: 'Скорость',
          value: '↓ ${_speedCompact(downSpeed)}   ↑ ${_speedCompact(upSpeed)}',
          mono: true,
        ),
      ],
    );
  }

  static String _bytesCompact(int b) {
    if (b < 1024) return '${b} Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} МБ';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  static String _speedCompact(double bps) {
    if (bps < 1024) return '${bps.toInt()} Б/с';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(0)} КБ/с';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} МБ/с';
  }
}

class _SubscriptionSection extends ConsumerWidget {
  const _SubscriptionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
    final rawName = activeProfile?.name ?? '';
    // Mask: show last 4 characters only.
    final masked = rawName.length > 4
        ? '•••• ${rawName.substring(rawName.length - 4)}'
        : (rawName.isEmpty ? '—' : rawName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, 'Подписка'),
        _hairline(context),
        _Row(
          label: 'Ключ',
          value: masked,
          mono: true,
          trailing: Icon(Icons.copy_outlined,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          onTap: () async {
            if (rawName.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: rawName));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Скопировано')),
              );
            }
          },
        ),
      ],
    );
  }
}

class _SettingsSection extends ConsumerWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, 'Настройки'),
        _hairline(context),
        _Row(
          label: 'Автоподключение при запуске',
          valueWidget: Switch(value: false, onChanged: (_) {}),
        ),
        _hairline(context),
        _Row(label: 'Язык', value: 'Русский', onTap: () {}),
        _hairline(context),
        _Row(label: 'Для разработчика', onTap: () {}),
      ],
    );
  }
}

class _FooterRow extends ConsumerWidget {
  const _FooterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(appInfoProvider).valueOrNull?.presentVersion ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kRowPadH, 32, _kRowPadH, 12),
      child: Text(
        'v$version · Поддержка @pixellnet_support',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

/// v0.1.26: Banner «Есть свежая версия» на Home.
/// Синтез app-designer + linguist: короткий title + одна CTA + крестик.
/// Тап на текст = скачать сразу, крестик = скрыть на 3 дня.
class _UpdateAvailableBanner extends ConsumerWidget {
  const _UpdateAvailableBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoUpdateStateProvider);
    if (!state.shouldShowBanner) return const SizedBox.shrink();
    final info = state.available!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: PixellnetBrand.mocha.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => UpdateDialog(info: info),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded,
                    color: PixellnetBrand.mochaOnDark, size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    'Есть свежая версия · ${info.version}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: PixellnetBrand.mochaOnDark,
                    ),
                  ),
                ),
                Text('Обновить',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: PixellnetBrand.mochaOnDark,
                        fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: PixellnetBrand.textSecondary,
                  tooltip: 'Скрыть на 3 дня',
                  onPressed: () =>
                      ref.read(autoUpdateStateProvider.notifier).dismissBanner(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// v0.1.26: Post-update banner «Обновлено до X · Что нового →».
/// Показывается 3 дня после установки. Читает Preferences.lastInstalledAt.
class _PostUpdateBanner extends ConsumerWidget {
  const _PostUpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(Preferences.lastInstalledAt);
    final version = ref.watch(Preferences.lastInstalledVersion);
    if (ts == 0 || version.isEmpty) return const SizedBox.shrink();

    // Показываем не дольше 3 дней после установки.
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageMs = now - ts;
    if (ageMs > const Duration(days: 3).inMilliseconds) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: PixellnetBrand.olive.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            // v0.1.28: showModalBottomSheet с ChangelogSheet — категории
            // «Новое / Починили / Стало лучше». Данные тянем с GH release body.
            final changelog = await _fetchChangelog(version);
            if (!context.mounted) return;
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: false,
              builder: (_) => ChangelogSheet(version: version, rawChangelog: changelog),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: PixellnetBrand.olive, size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    'Обновлено до $version',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: PixellnetBrand.olive,
                    ),
                  ),
                ),
                Text('Что нового →',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: PixellnetBrand.olive, fontWeight: FontWeight.w700)),
                const Gap(4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: PixellnetBrand.textSecondary,
                  tooltip: 'Скрыть',
                  onPressed: () async {
                    await ref.read(Preferences.lastInstalledAt.notifier).update(0);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// v0.1.34: Banner для VPN permission recovery.
///
/// Показывается в двух состояниях:
///   [VpnPermissionState.requesting] — системный диалог уже открыт автоматически,
///     показываем мягкую подсказку с spinner.
///   [VpnPermissionState.needsPermission] — юзер закрыл диалог или авто-открытие
///     не удалось, показываем кнопку "Разрешить VPN".
///
/// Design: такой же стиль как _UpdateAvailableBanner (Material с цветом error).
/// Не блокирует UI — это overlay Positioned, не диалог.
class _VpnPermissionBanner extends ConsumerWidget {
  const _VpnPermissionBanner({required this.state});

  final VpnPermissionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (state == VpnPermissionState.requesting) {
      return Material(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  'Запрашиваем разрешение на соединение...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // needsPermission — ручная кнопка
    return Material(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ref.read(vpnPermissionRecoveryProvider.notifier).retryPermission(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(
                Icons.vpn_key_rounded,
                color: theme.colorScheme.onErrorContainer,
                size: 20,
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Нужно разрешение на соединение',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Нажмите чтобы разрешить и переподключиться',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(4),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    ref.read(vpnPermissionRecoveryProvider.notifier).retryPermission(),
                child: const Text('Разрешить'),
              ),
              const Gap(4),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.7),
                tooltip: 'Скрыть',
                onPressed: () =>
                    ref.read(vpnPermissionRecoveryProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// v0.1.28: тянет release body с GH API (первый источник для changelog).
/// Fallback — пустая строка (ChangelogSheet покажет generic-текст).
Future<String> _fetchChangelog(String version) async {
  try {
    final resp = await http
        .get(Uri.parse(
            'https://api.github.com/repos/AMX72/pixellnet-client/releases/tags/v$version'))
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return '';
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['body'] as String?) ?? '';
  } catch (_) {
    return '';
  }
}
