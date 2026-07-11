import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/pin_coin_painter.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// PiN button — единственный focal point главного экрана.
///
/// Спецификация (см. docs/knowledge-visual-details-v3.md):
///   - Диаметр 180dp (компромисс 220 visual / 160 ergonomics для 6.5")
///   - Текст «PiN» — Inter 56sp weight 700 letter-spacing -1.5
///   - 5 состояний: idle / connecting / connected / disconnecting / error
///   - Анимации: pulse (connecting), scale-back (connected), shake (error)
class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull ?? false;
    final buttonTheme = Theme.of(context).extension<ConnectionButtonTheme>() ?? ConnectionButtonTheme.light;

    final onTap = switch (connectionStatus) {
      AsyncData(value: Connected()) when requiresReconnect => () async {
            final activeProfile = await ref.read(activeProfileProvider.future);
            return ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
          },
      AsyncData(value: Disconnected()) || AsyncError() => () async {
            if (ref.read(activeProfileProvider).valueOrNull == null) {
              await ref.read(dialogNotifierProvider.notifier).showNoActiveProfile();
              ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
              return;
            }
            if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
              return ref.read(connectionNotifierProvider.notifier).toggleConnection();
            }
          },
      AsyncData(value: Connected()) => () {
            ref.read(connectionNotifierProvider.notifier).toggleConnection();
          },
      _ => () {},
    };

    final (label, subtitle, color, animState) = _stateFor(connectionStatus, requiresReconnect, buttonTheme, t);

    final enabled = switch (connectionStatus) {
      AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
      _ => false,
    };

    // Маппинг из ConnectionStatus → PinCoinState (палитра монеты)
    final coinState = switch (connectionStatus) {
      AsyncData(value: Connected()) when requiresReconnect => PinCoinState.connecting,
      AsyncData(value: Connected()) => PinCoinState.connected,
      AsyncData(value: Connecting()) => PinCoinState.connecting,
      AsyncData(value: Disconnecting()) => PinCoinState.connecting,
      AsyncError() => PinCoinState.error,
      _ => PinCoinState.idle,
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PinButton(
          onTap: onTap,
          enabled: enabled,
          label: label,
          coinState: coinState,
          animState: animState,
        ),
        const Gap(20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            subtitle,
            key: ValueKey(subtitle),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PixellnetBrand.textSecondary,
                  letterSpacing: 0.1,
                ),
          ),
        ),
      ],
    );
  }

  /// Возвращает (label, subtitle, fillColor, animState) для состояния.
  (String, String, Color, _PinAnim) _stateFor(
    AsyncValue<ConnectionStatus> status,
    bool requiresReconnect,
    ConnectionButtonTheme theme,
    TranslationsEn t,
  ) {
    return switch (status) {
      AsyncData(value: Connected()) when requiresReconnect => (
          'PIN',
          t.connection.reconnect,
          theme.connectingColor!,
          _PinAnim.pulse,
        ),
      AsyncData(value: Connected()) => (
          'PIN',
          t.connection.connected,
          theme.connectedColor!,
          _PinAnim.connected,
        ),
      AsyncData(value: Connecting()) => (
          'PIN',
          t.connection.connecting,
          theme.connectingColor!,
          _PinAnim.pulse,
        ),
      AsyncData(value: Disconnecting()) => (
          'PIN',
          t.connection.disconnecting,
          theme.connectingColor!,
          _PinAnim.pulse,
        ),
      AsyncError() => (
          'PIN',
          t.connection.tapToConnect,
          theme.errorColor!,
          _PinAnim.shake,
        ),
      _ => (
          'PIN',
          t.connection.tapToConnect,
          theme.idleColor!,
          _PinAnim.idle,
        ),
    };
  }
}

enum _PinAnim { idle, pulse, connected, shake }

class _PinButton extends StatelessWidget {
  const _PinButton({
    required this.onTap,
    required this.enabled,
    required this.label,
    required this.coinState,
    required this.animState,
  });

  final VoidCallback onTap;
  final bool enabled;
  final String label;
  final PinCoinState coinState;
  final _PinAnim animState;

  static const double _size = 180;

  @override
  Widget build(BuildContext context) {
    // Плавный transition палитр — 240ms Color.lerp через TweenAnimationBuilder
    // (мгновенно для error чтобы shake сигнализировал).
    final target = paletteFor(coinState);
    final transitionMs = coinState == PinCoinState.error ? 0 : 240;

    Widget button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.0),
        duration: Duration(milliseconds: transitionMs),
        curve: Curves.easeInOutCubic,
        builder: (context, t, child) {
          // При каждой смене palette Flutter ре-строит с новым target — прямо
          // передаём target в painter (плавность даёт AnimatedSwitcher поверх).
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: target.glow.withValues(alpha: target.glowAlpha),
                  blurRadius: target.glowBlur,
                  spreadRadius: target.glowSpread,
                ),
              ],
            ),
            child: SizedBox(
              width: _size,
              height: _size,
              child: Material(
                key: const ValueKey('home_connection_button'),
                shape: const CircleBorder(),
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  splashColor: target.rim.withValues(alpha: 0.20),
                  highlightColor: Colors.white.withValues(alpha: 0.04),
                  child: CustomPaint(
                    painter: PinCoinPainter(
                      palette: target,
                      label: label,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    switch (animState) {
      case _PinAnim.pulse:
        button = button
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(begin: 1.0, end: 0.94, duration: 1200.ms, curve: Curves.easeInOut);
      case _PinAnim.connected:
        button = button
            .animate()
            .scaleXY(begin: 1.0, end: 1.08, duration: 200.ms, curve: Curves.easeOut)
            .then()
            .scaleXY(end: 1.0, duration: 200.ms, curve: Curves.easeOutBack);
      case _PinAnim.shake:
        button = button
            .animate(onPlay: (c) => c.repeat())
            .shake(duration: 500.ms, hz: 3, offset: const Offset(8, 0));
      case _PinAnim.idle:
        break;
    }

    return button.animate(target: enabled ? 0 : 1).blurXY(end: 1);
  }
}
