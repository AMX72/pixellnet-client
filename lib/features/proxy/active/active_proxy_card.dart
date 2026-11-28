import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/channel_status.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ActiveProxyFooter extends ConsumerWidget with InfraLogger {
  const ActiveProxyFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(
      connectionNotifierProvider.select((value) => value.valueOrNull ?? const Disconnected()),
    );

    final activeProxy = ref.watch(activeProxyNotifierProvider.select((value) => value.valueOrNull));
    final t = ref.watch(translationsProvider).requireValue;

    // Early return if required data is not available
    if (connectionState != const Connected() || activeProxy == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    // Handle URL test in a way that won't trigger during build
    Future<void> handleUrlTest() async {
      try {
        if (!context.mounted) return;
        await ref.read(activeProxyNotifierProvider.notifier).urlTest("");
      } catch (e) {
        // Handle error here
        loggy.error("Error during URL test: $e");
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withOpacity(1),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: theme.colorScheme.secondary.withOpacity(.21), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: InkWell(
        onTap: () {
          context.goNamed('proxies');
        },
        child: Row(
          children: [
            InkWell(
              onTap: () async {
                await handleUrlTest();
                await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: activeProxy);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: IPCountryFlag(
                  countryCode: activeProxy.ipinfo.countryCode,
                  organization: activeProxy.ipinfo.org,
                  size: 48,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // v0.1.22: 2-строчная структура (app-designer bimodal spec).
                  // Title: страна · имя канала — понятно и домохозяйке.
                  // Subtitle: качество + пинг — IT-юзеру нужное.
                  Semantics(
                    label: t.pages.proxies.activeProxy,
                    child: Text(
                      _titleFor(t, activeProxy),
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitleFor(t, activeProxy),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.arrow_forward_ios, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }
}

String getRealOutboundTag(OutboundInfo group) {
  var tag = group.tagDisplay;
  if (group.groupSelectedTagDisplay != "" && group.groupSelectedTagDisplay != tag) {
    tag = "$tag → ${group.groupSelectedTagDisplay}";
  }
  return tag;
}

/// v0.1.22: title сервер-карточки — «Германия · Matrix» (без «lowest→»).
String _titleFor(Translations t, OutboundInfo p) {
  final country = countryName(t, p.ipinfo.countryCode);
  final name = p.groupSelectedTagDisplay.isNotEmpty ? p.groupSelectedTagDisplay : p.tagDisplay;
  if (country.isEmpty) return name;
  return '$country · $name';
}

/// subtitle — «Работает · 45 мс» вместо IP + protocol. Подпись канала — вариант «В» (владелец 28.11):
/// «Работает» / «Не отвечает» / «Проверяем связь…»; миллисекунды — только когда канал ответил.
String _subtitleFor(Translations t, OutboundInfo p) {
  final delay = p.urlTestDelay;
  final status = channelStatusLabel(t, delay);
  if (delay <= 0 || delay >= 65000) return status;
  return '$status · ${t.ui.common.ms(ms: delay)}';
}

// class _StatsColumn extends HookConsumerWidget {
//   const _StatsColumn();

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final t = ref.watch(translationsProvider).requireValue;
//     final stats = ref.watch(statsNotifierProvider).value;

//     return Directionality(
//       textDirection: TextDirection.values[(Directionality.of(context).index + 1) % TextDirection.values.length],
//       child: Flexible(
//         child: Column(
//           children: [
//             _InfoProp(
//               icon: FluentIcons.arrow_bidirectional_up_down_20_regular,
//               text: (stats?.downlinkTotal ?? 0).size(),
//               semanticLabel: t.stats.totalTransferred,
//             ),
//             const Gap(8),
//             _InfoProp(
//               icon: FluentIcons.arrow_download_20_regular,
//               text: (stats?.downlink ?? 0).speed(),
//               semanticLabel: t.stats.speed,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _InfoProp extends StatelessWidget {
//   const _InfoProp({
//     required this.icon,
//     required this.text,
//     this.semanticLabel,
//   });

//   final IconData icon;
//   final String text;
//   final String? semanticLabel;

//   @override
//   Widget build(BuildContext context) {
//     return Semantics(
//       label: semanticLabel,
//       child: Row(
//         children: [
//           Icon(icon),
//           const Gap(8),
//           Flexible(
//             child: Text(
//               text,
//               style: Theme.of(context).textTheme.labelMedium?.copyWith(fontFamily: FontFamily.emoji),
//               overflow: TextOverflow.ellipsis,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
