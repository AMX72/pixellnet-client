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

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PinButton(
          onTap: onTap,
          enabled: enabled,
          color: color,
          textColor: buttonTheme.textColor ?? const Color(0xFF1A1917),
          label: label,
          state: animState,
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
          'PiN',
          t.connection.reconnect,
          theme.connectingColor!,
          _PinAnim.pulse,
        ),
      AsyncData(value: Connected()) => (
          'PiN',
          t.connection.connected,
          theme.connectedColor!,
          _PinAnim.connected,
        ),
      AsyncData(value: Connecting()) => (
          'PiN',
          t.connection.connecting,
          theme.connectingColor!,
          _PinAnim.pulse,
        ),
      AsyncData(value: Disconnecting()) => (
          'PiN',
          t.connection.disconnecting,
          theme.connectingColor!,
          _PinAnim.pulse,
        ),
      AsyncError() => (
          'PiN',
          t.connection.tapToConnect,
          theme.errorColor!,
          _PinAnim.shake,
        ),
      _ => (
          'PiN',
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
    required this.color,
    required this.textColor,
    required this.label,
    required this.state,
  });

  final VoidCallback onTap;
  final bool enabled;
  final Color color;
  final Color textColor;
  final String label;
  final _PinAnim state;

  static const double _size = 180;

  @override
  Widget build(BuildContext context) {
    Widget button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Material(
          key: const ValueKey('home_connection_button'),
          shape: const CircleBorder(),
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            splashColor: PixellnetBrand.amber.withValues(alpha: 0.20),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  height: 1.0,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    switch (state) {
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
