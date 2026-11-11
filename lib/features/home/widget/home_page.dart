import 'dart:async';
import 'dart:convert';

import 'package:dartx/dartx.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/gen/translations.g.dart' show AppLocale;
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
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
                  const SliverToBoxAdapter(child: _SubscriptionSection()),
                  const SliverToBoxAdapter(child: _ExpirySection()),
                  const SliverToBoxAdapter(child: _ConnectionSection()),
                  const SliverToBoxAdapter(child: _TrafficSection()),
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
            const Icon(Icons.cloud_sync_outlined, size: 36),
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
                          Icon(Icons.download_outlined,
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
                          Icon(Icons.upload_outlined,
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
                  icon: const Icon(Icons.copy_outlined, size: 18),
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
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: _kRowPadH, vertical: 7),
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
            // Right gutter is always reserved so every row's value column
            // ends at the same x coordinate, regardless of whether a chevron
            // or custom trailing is shown. Width = 6 gap + 18 icon = 24.
            const Gap(6),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant)
            else
              const SizedBox(width: 18),
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

    final t = ref.watch(translationsProvider).requireValue;
    if (conn is Connected) {
      dotColor = PixellnetBrand.success;
      statusTitle = t.connection.connected;
      final name = active?.tagDisplay.isNotEmpty == true
          ? active!.tagDisplay
          : (active?.tag ?? '—');
      final delay = active?.urlTestDelay ?? 0;
      final delayPart = delay > 0 && delay < 65000 ? ' · $delay мс' : '';
      subtitle = '$name$delayPart';
      buttonLabel = t.connection.disconnect;
      buttonFilled = false;
    } else if (conn is Connecting) {
      dotColor = PixellnetBrand.warning;
      statusTitle = t.connection.connecting;
      subtitle = t.pages.home.establishing;
      buttonLabel = t.pages.home.cancel;
      buttonFilled = false;
      animateDot = true;
    } else {
      dotColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
      statusTitle = t.pages.home.notConnected;
      subtitle = t.connection.tapToConnect;
      buttonLabel = t.connection.connect;
      buttonFilled = true;
    }

    // Данные для inline-ссылок Сервер/Ключ.
    final serverName = active?.tagDisplay.isNotEmpty == true
        ? active!.tagDisplay
        : (active?.tag.isNotEmpty == true ? active!.tag : 'Авто');
    final delay = active?.urlTestDelay ?? 0;
    final delayPart = delay > 0 && delay < 65000 ? ' · $delay мс' : '';
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
    final all = ref.watch(profilesNotifierProvider).valueOrNull ?? const [];
    final extraCount = (all.length - 1).clamp(0, 99);
    final keyMasked = _maskProfile(activeProfile?.name ?? '');
    final keyText = extraCount > 0 ? '$keyMasked · +$extraCount' : keyMasked;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kRowPadH, 16, _kRowPadH, 14),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const Gap(10),
          _HeroInlineRow(
            label: null,
            value: '$serverName$delayPart',
            mono: true,
            onTap: () => _showServerSheet(context, ref),
          ),
          const Gap(14),
          SizedBox(
            width: double.infinity,
            height: 42,
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
    final t = ref.watch(translationsProvider).requireValue;
    final active = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final protocol = active?.type.isNotEmpty == true ? active!.type : 'Auto';
    final mode = ref.watch(ConfigOptions.serviceMode);
    final modeLabel = _serviceModeLabel(mode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _Row(
          label: t.pages.home.protocol,
          value: protocol,
          onTap: () => _showPlaceholderSheet(context, t.pages.home.protocol,
              'Протокол определяется автоматически для каждого сервера. Для смены — выберите другой сервер выше.'),
        ),
        _Row(
          label: t.pages.home.mode,
          value: modeLabel,
          onTap: () => _showModeSheet(context, ref),
        ),
      ],
    );
  }
}

String _serviceModeLabel(ServiceMode m) {
  switch (m) {
    case ServiceMode.tun: return 'VPN (TUN)';
    case ServiceMode.systemProxy: return 'Системный прокси';
    case ServiceMode.proxy: return 'Прокси-порт';
  }
}

void _showModeSheet(BuildContext context, WidgetRef ref) {
  final current = ref.read(ConfigOptions.serviceMode);
  final choices = ServiceMode.choices;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Режим работы',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            for (final m in choices)
              InkWell(
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (m != current) {
                    await ref.read(ConfigOptions.serviceMode.notifier).update(m);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _serviceModeLabel(m),
                              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                            ),
                            if (m == ServiceMode.tun)
                              Text('Рекомендуется — работает со всеми приложениями',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                            if (m == ServiceMode.systemProxy)
                              Text('Только HTTP/HTTPS, ломает Node.js и Docker',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                            if (m == ServiceMode.proxy)
                              Text('Для продвинутых — SOCKS5 порт',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (m == current)
                        Icon(Icons.check_outlined, size: 18, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            const Gap(8),
          ],
        ),
      );
    },
  );
}

void _showServerSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.75,
    ),
    builder: (ctx) {
      return const _ServerPickerBody();
    },
  );
}

class _ServerPickerBody extends ConsumerWidget {
  const _ServerPickerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final proxies = ref.watch(proxiesOverviewNotifierProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Выбор сервера',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_outlined, size: 20),
                  tooltip: 'Обновить список',
                  color: theme.colorScheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () async {
                    final active = ref.read(activeProfileProvider).valueOrNull;
                    if (active is RemoteProfileEntity) {
                      await ref
                          .read(updateProfileNotifierProvider(active.id).notifier)
                          .updateProfile(active);
                    }
                  },
                ),
                if (proxies.valueOrNull != null)
                  IconButton(
                    icon: const Icon(Icons.speed_outlined, size: 20),
                    tooltip: 'Проверить пинг',
                    color: theme.colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () async {
                      final g = proxies.valueOrNull;
                      if (g == null) return;
                      await ref
                          .read(proxiesOverviewNotifierProvider.notifier)
                          .urlTest(g.tag);
                    },
                  ),
              ],
            ),
          ),
          Flexible(
            child: switch (proxies) {
              AsyncData(value: final group?) => _ServerList(group: group),
              AsyncData() => _ServerEmpty(msg: 'Нет серверов — добавьте ключ подписки.'),
              AsyncError(:final error) => _ServerEmpty(
                  msg: error.toString().contains('ServiceNotRunning')
                      ? 'Подключитесь, чтобы увидеть список серверов'
                      : 'Ошибка загрузки: $error',
                ),
              _ => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            },
          ),
          const Gap(8),
        ],
      ),
    );
  }
}

class _ServerEmpty extends StatelessWidget {
  const _ServerEmpty({required this.msg});
  final String msg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Text(
        msg,
        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ServerList extends ConsumerWidget {
  const _ServerList({required this.group});
  final OutboundGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = group.items;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            InkWell(
              onTap: () async {
                Navigator.of(context).pop();
                if (item.tag != group.selected) {
                  await ref
                      .read(proxiesOverviewNotifierProvider.notifier)
                      .changeProxy(group.tag, item.tag);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.tagDisplay.isNotEmpty ? item.tagDisplay : item.tag,
                            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                          ),
                          if (item.type.isNotEmpty)
                            Text(item.type,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                        ],
                      ),
                    ),
                    Text(
                      item.urlTestDelay > 0 && item.urlTestDelay < 65000
                          ? '${item.urlTestDelay} мс'
                          : '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Consolas',
                        color: _pingColor(item.urlTestDelay, theme),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Gap(10),
                    if (item.tag == group.selected)
                      Icon(Icons.check_outlined, size: 18, color: theme.colorScheme.primary)
                    else
                      const SizedBox(width: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _pingColor(int delayMs, ThemeData theme) {
    if (delayMs <= 0 || delayMs >= 65000) return theme.colorScheme.onSurfaceVariant;
    if (delayMs < 80) return PixellnetBrand.success;
    if (delayMs < 250) return theme.colorScheme.onSurface;
    return PixellnetBrand.warning;
  }
}

void _showPlaceholderSheet(BuildContext context, String title, String msg) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(ctx).colorScheme.onSurface,
                )),
            const Gap(8),
            Text(msg,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    ),
  );
}

class _TrafficSection extends ConsumerWidget {
  const _TrafficSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionNotifierProvider).valueOrNull;
    if (conn is! Connected) return const SizedBox.shrink();

    final stats = ref.watch(statsNotifierProvider).valueOrNull;
    final upSpeed = (stats?.uplink.toInt() ?? 0).toDouble();
    final downSpeed = (stats?.downlink.toInt() ?? 0).toDouble();
    final totalUp = stats?.uplinkTotal.toInt() ?? 0;
    final totalDown = stats?.downlinkTotal.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _Row(
          label: 'Сегодня',
          value: '↓ ${_bytesCompact(totalDown)}   ↑ ${_bytesCompact(totalUp)}',
          mono: true,
        ),
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

/// Compact inline row inside the status hero (label · value › ).
/// Used for Сервер/Ключ shortcuts above the Connect button.
class _HeroInlineRow extends StatelessWidget {
  const _HeroInlineRow({
    this.label,
    required this.value,
    this.mono = false,
    required this.onTap,
  });

  final String? label;
  final String value;
  final bool mono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        child: Row(
          children: [
            if (label != null)
              Text(
                '${label!}: ',
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                  fontFamily: mono ? 'Consolas' : null,
                  fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Gap(6),
            Icon(Icons.chevron_right_outlined,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Row «Срок» на главной — сразу под Ключ. Показывает expiry с color-code
/// по оставшимся дням (>30 muted, 7-30 accent, <7 warning, ≤0 error).
/// Tap → renew bottom-sheet.
class _ExpirySection extends ConsumerWidget {
  const _ExpirySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
    if (activeProfile is! RemoteProfileEntity) return const SizedBox.shrink();
    final sub = activeProfile.subInfo;
    if (sub == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final daysLeft = sub.expire.difference(now).inDays;
    final (color, valueText) = _expiryStyle(sub.expire, daysLeft, theme);

    return InkWell(
      onTap: () => _showRenewSheet(context, activeProfile, sub),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: _kRowPadH, vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Срок',
                style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
              ),
            ),
            Flexible(
              child: Text(
                valueText,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
            const Gap(6),
            Icon(Icons.chevron_right_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  (Color, String) _expiryStyle(DateTime expire, int daysLeft, ThemeData theme) {
    final dateText = _ProfileRow._fmtDate(expire);
    if (daysLeft <= 0) {
      return (PixellnetBrand.error, 'срок истёк');
    }
    final suffix = _daysWord(daysLeft);
    final text = 'до $dateText · $daysLeft $suffix';
    // Highlight only when running out (<7 days). Otherwise neutral muted.
    if (daysLeft < 7) return (PixellnetBrand.warning, text);
    return (theme.colorScheme.onSurfaceVariant, text);
  }

  static String _daysWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'день';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return 'дня';
    return 'дней';
  }
}

void _showRenewSheet(BuildContext context, RemoteProfileEntity profile, SubscriptionInfo sub) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final daysLeft = sub.expire.difference(DateTime.now()).inDays;
      final masked = _maskProfile(profile.name);
      final dateStr = _ProfileRow._fmtDate(sub.expire);
      final subtitleText = daysLeft <= 0
          ? 'Ключ $masked · срок истёк'
          : 'Ключ $masked истекает через $daysLeft ${_ExpirySection._daysWord(daysLeft)} ($dateStr)';

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Продление подписки',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface),
              ),
              const Gap(8),
              Text(
                subtitleText,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              ),
              const Gap(20),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Продлить в Telegram'),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final uri = Uri.parse('https://t.me/pixellnet_bot?start=renew');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
              ),
              const Gap(10),
              Text(
                'Другие тарифы и способы оплаты — в @pixellnet_bot',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const Gap(8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Row «Ключ» в основном списке (под кнопкой Подключить).
class _SubscriptionSection extends ConsumerWidget {
  const _SubscriptionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
    final all = ref.watch(profilesNotifierProvider).valueOrNull ?? const [];
    final extraCount = (all.length - 1).clamp(0, 99);
    final rawName = activeProfile?.name ?? '';
    final masked = _maskProfile(rawName);
    final valueText = extraCount > 0 ? '$masked · +$extraCount' : masked;
    return _Row(
      label: t.pages.home.key,
      value: valueText,
      mono: true,
      onTap: () => _showSubscriptionSheet(context, ref),
    );
  }
}

String _maskProfile(String name) {
  if (name.isEmpty) return '—';
  if (name.length <= 4) return name;
  return '•••• ${name.substring(name.length - 4)}';
}

String _profileDisplayName(ProfileEntity p, int index) {
  if (p.name.trim().isNotEmpty && !p.name.startsWith('http')) return p.name;
  return 'Подписка ${index + 1}';
}

void _showSubscriptionSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.75,
    ),
    builder: (ctx) => const _SubscriptionSheetBody(),
  );
}

class _SubscriptionSheetBody extends ConsumerWidget {
  const _SubscriptionSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const [];
    // Active first, rest by order (upstream sorts by lastUpdate).
    final sorted = [...profiles]..sort((a, b) {
      if (a.active && !b.active) return -1;
      if (!a.active && b.active) return 1;
      return 0;
    });
    final title = profiles.length > 1 ? 'Ключи' : 'Ключ';
    final activeList = sorted.where((p) => p.active).toList();
    final active = activeList.isEmpty ? null : activeList.first;
    final activeIndex = active == null ? 0 : sorted.indexOf(active);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_paste_outlined, size: 20),
                  tooltip: 'Вставить из буфера',
                  color: theme.colorScheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final text = data?.text?.trim();
                    if (text == null || text.isEmpty) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('В буфере нет ключа')),
                      );
                      return;
                    }
                    await ref.read(addProfileNotifierProvider.notifier).addClipboard(text);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Добавлено')),
                    );
                  },
                ),
              ],
            ),
          ),
          if (active != null)
            _ActiveKeyHero(profile: active, displayName: _profileDisplayName(active, activeIndex)),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (int i = 0; i < sorted.length; i++)
                    _ProfileRow(profile: sorted[i], index: i),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => _showAddSubscriptionSheet(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.add_outlined, size: 20, color: theme.colorScheme.primary),
                  const Gap(12),
                  Text(
                    'Добавить подписку',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(4),
        ],
      ),
    );
  }
}

class _ActiveKeyHero extends StatefulWidget {
  const _ActiveKeyHero({required this.profile, required this.displayName});
  final ProfileEntity profile;
  final String displayName;

  @override
  State<_ActiveKeyHero> createState() => _ActiveKeyHeroState();
}

class _ActiveKeyHeroState extends State<_ActiveKeyHero> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyOrUrl = widget.profile is RemoteProfileEntity
        ? (widget.profile as RemoteProfileEntity).url
        : widget.profile.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Активный ключ · ${widget.displayName}',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const Gap(6),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2022),
                border: Border.all(color: const Color(0xFF2E2F31), width: 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                keyOrUrl,
                maxLines: _expanded ? null : 3,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Consolas',
                  color: theme.colorScheme.onSurface,
                  height: 1.3,
                ),
              ),
            ),
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: _HeroAction(
                  icon: Icons.copy_outlined,
                  label: 'Копировать',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: keyOrUrl));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано'), duration: Duration(seconds: 2)),
                    );
                  },
                ),
              ),
              Expanded(
                child: _HeroAction(
                  icon: Icons.ios_share_outlined,
                  label: 'Поделиться',
                  onTap: () async {
                    await Share.share(keyOrUrl, subject: 'PIXELLNET · ${widget.displayName}');
                  },
                ),
              ),
              Expanded(
                child: _HeroAction(
                  icon: Icons.qr_code_outlined,
                  label: 'QR-код',
                  onTap: () => _showQrSheet(context, keyOrUrl, widget.displayName),
                ),
              ),
            ],
          ),
          const Gap(10),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const Gap(4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showQrSheet(BuildContext context, String data, String displayName) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: data,
                size: 280,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const Gap(16),
            Text(
              displayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
            ),
            const Gap(6),
            const Text(
              'Сканируйте другим устройством',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const Gap(16),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.primary),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    },
  );
}

class _ProfileRow extends ConsumerWidget {
  const _ProfileRow({required this.profile, required this.index});
  final ProfileEntity profile;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final displayName = _profileDisplayName(profile, index);
    final masked = _maskProfile(profile.name);
    String? subLine;
    if (profile is RemoteProfileEntity) {
      final rp = profile as RemoteProfileEntity;
      final sub = rp.subInfo;
      if (sub != null) {
        final days = sub.expire.difference(DateTime.now()).inDays;
        if (days > 0) {
          subLine = 'действует до ${_fmtDate(sub.expire)}';
        } else if (days < 0) {
          subLine = 'срок истёк';
        }
      }
      subLine ??= Uri.tryParse(rp.url)?.host;
    }

    return InkWell(
      onTap: profile.active
          ? null
          : () async {
              await ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              profile.active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: profile.active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        masked,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Consolas',
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (subLine != null) ...[
                    const Gap(2),
                    Text(
                      subLine,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
              padding: EdgeInsets.zero,
              tooltip: '',
              onSelected: (value) => _onAction(context, ref, value),
              itemBuilder: (ctx) => [
                if (profile is RemoteProfileEntity)
                  const PopupMenuItem(value: 'refresh', child: Text('Обновить')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Удалить',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'refresh':
        if (profile is RemoteProfileEntity) {
          await ref
              .read(updateProfileNotifierProvider(profile.id).notifier)
              .updateProfile(profile as RemoteProfileEntity);
        }
        break;
      case 'delete':
        await _confirmAndDelete(context, ref, profile);
        break;
    }
  }

  static String _fmtDate(DateTime d) {
    const months = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return '${d.day} ${months[d.month - 1]}';
  }
}

Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref, ProfileEntity profile) async {
  final all = ref.read(profilesNotifierProvider).valueOrNull ?? const [];
  final isLast = all.length <= 1;
  final isActive = profile.active;
  final others = all.where((p) => p.id != profile.id).toList();

  if (isLast || isActive) {
    final msg = isLast
        ? 'После удаления приложение потребует новый ключ. Удалить?'
        : 'Активной станет "${_profileDisplayName(others.first, 0)}". Это действие нельзя отменить.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить "${_profileDisplayName(profile, 0)}"?'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
  if (!context.mounted) return;
  if (!isLast && !isActive) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Подписка удалена'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            if (profile is RemoteProfileEntity) {
              await ref.read(addProfileNotifierProvider.notifier).addClipboard(profile.url);
            }
          },
        ),
      ),
    );
  }
}

void _showAddSubscriptionSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Добавить подписку',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_outlined, size: 20),
              title: const Text('Вставить из буфера', style: TextStyle(fontSize: 14)),
              onTap: () async {
                final data = await Clipboard.getData('text/plain');
                final text = data?.text?.trim();
                if (text == null || text.isEmpty) {
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Буфер пуст')),
                  );
                  return;
                }
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                await ref.read(addProfileNotifierProvider.notifier).addClipboard(text);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Ввести вручную', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.of(ctx).pop();
                _showManualEntryDialog(context, ref);
              },
            ),
            const Gap(8),
          ],
        ),
      );
    },
  );
}

Future<void> _showManualEntryDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Новая подписка'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Ключ или URL подписки',
          border: OutlineInputBorder(),
        ),
        maxLines: 2,
        minLines: 1,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Активировать'),
        ),
      ],
    ),
  );
  if (result != null && result.isNotEmpty) {
    await ref.read(addProfileNotifierProvider.notifier).addClipboard(result);
  }
}

class _SettingsSection extends ConsumerWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final locale = ref.watch(localePreferencesProvider);
    final langLabel = _localeLabel(locale);
    final autoStart = ref.watch(autoStartNotifierProvider).valueOrNull ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _Row(
          label: t.pages.home.autoConnect,
          valueWidget: Switch(
            value: autoStart,
            onChanged: (v) async {
              if (v) {
                await ref.read(autoStartNotifierProvider.notifier).enable();
              } else {
                await ref.read(autoStartNotifierProvider.notifier).disable();
              }
            },
          ),
        ),
        _Row(
          label: t.pages.home.language,
          value: langLabel,
          onTap: () => _showLanguageSheet(context, ref),
        ),
        _Row(
          label: t.pages.home.developer,
          onTap: () => _showPlaceholderSheet(context, t.pages.home.developer, t.pages.home.developerSoon),
        ),
      ],
    );
  }
}

String _localeLabel(AppLocale locale) {
  // Native name per locale; CIS languages first, then existing upstream.
  const names = <String, String>{
    // CIS pack
    'ru': 'Русский',
    'uk': 'Українська',
    'be': 'Беларуская',
    'kk': 'Қазақша',
    'ky': 'Кыргызча',
    'uz': 'Oʻzbekcha',
    'tg': 'Тоҷикӣ',
    'tk': 'Türkmençe',
    'az': 'Azərbaycanca',
    'hy': 'Հայերեն',
    'ka': 'ქართული',
    // Upstream
    'en': 'English',
    'ar': 'العربية',
    'es': 'Español',
    'fa': 'فارسی',
    'fr': 'Français',
    'id': 'Bahasa Indonesia',
    'tr': 'Türkçe',
    'pt-BR': 'Português (BR)',
    'pt_BR': 'Português (BR)',
    'zh-CN': '中文 (简体)',
    'zh_CN': '中文 (简体)',
    'zh-TW': '中文 (繁體)',
    'zh_TW': '中文 (繁體)',
    'de': 'Deutsch',
    'it': 'Italiano',
    'ja': '日本語',
    'ko': '한국어',
    'vi': 'Tiếng Việt',
    'pl': 'Polski',
  };
  final key = locale.languageTag;
  return names[key] ?? names[locale.languageCode] ?? key.toUpperCase();
}

void _showLanguageSheet(BuildContext context, WidgetRef ref) {
  final t = ref.read(translationsProvider).requireValue;
  final current = ref.read(localePreferencesProvider);
  // Order: Russian first, CIS pack, then rest alphabetical.
  const priority = <String>['ru', 'uk', 'be', 'kk', 'ky', 'uz', 'tg', 'tk', 'az', 'hy', 'ka'];
  int rank(AppLocale l) {
    final tag = l.languageTag;
    final code = l.languageCode;
    final i = priority.indexOf(code);
    if (i >= 0) return i;
    final j = priority.indexOf(tag);
    if (j >= 0) return j;
    return 1000 + code.codeUnitAt(0);
  }
  final sorted = [...AppLocale.values]..sort((a, b) => rank(a).compareTo(rank(b)));
  final options = sorted.map((l) => (l, _localeLabel(l))).toList();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.75,
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                t.pages.home.languageTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final opt in options)
                      InkWell(
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          if (opt.$1 != current) {
                            await ref
                                .read(localePreferencesProvider.notifier)
                                .changeLocale(opt.$1);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  opt.$2,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (opt.$1 == current)
                                Icon(Icons.check_outlined,
                                    size: 18, color: theme.colorScheme.primary),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Gap(8),
          ],
        ),
      );
    },
  );
}

class _FooterRow extends ConsumerWidget {
  const _FooterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final version = ref.watch(appInfoProvider).valueOrNull?.presentVersion ?? '';
    final mutedColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kRowPadH, 20, _kRowPadH, 10),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 12, color: mutedColor),
          children: [
            TextSpan(text: 'v$version · ${t.pages.home.support} '),
            TextSpan(
              text: '@pixellnet_support',
              style: TextStyle(color: theme.colorScheme.primary),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _openTelegramSupport(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTelegramSupport() async {
    final uri = Uri.parse('https://t.me/pixellnet_support');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                Icon(Icons.system_update_outlined,
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
                  icon: const Icon(Icons.close_outlined, size: 18),
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
                Icon(Icons.check_circle_outlined, color: PixellnetBrand.olive, size: 20),
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
                  icon: const Icon(Icons.close_outlined, size: 18),
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
                Icons.vpn_key_outlined,
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
                icon: const Icon(Icons.close_outlined, size: 18),
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
