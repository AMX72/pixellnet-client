import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';

class ConnectionButtonTheme extends ThemeExtension<ConnectionButtonTheme> {
  const ConnectionButtonTheme({this.idleColor, this.connectedColor});

  final Color? idleColor;
  final Color? connectedColor;

  /// PIXELLNET palette v3:
  /// - Idle (не подключено) — brown mocha (нейтральный, «выключено»)
  /// - Connected (подключено) — olive success (Mullvad-style, «работает»)
  static const ConnectionButtonTheme light = ConnectionButtonTheme(
    idleColor: PixellnetColors.darkPrimary,
    connectedColor: PixellnetColors.success,
  );

  @override
  ThemeExtension<ConnectionButtonTheme> copyWith({Color? idleColor, Color? connectedColor}) => ConnectionButtonTheme(
    idleColor: idleColor ?? this.idleColor,
    connectedColor: connectedColor ?? this.connectedColor,
  );

  @override
  ThemeExtension<ConnectionButtonTheme> lerp(covariant ThemeExtension<ConnectionButtonTheme>? other, double t) {
    if (other is! ConnectionButtonTheme) {
      return this;
    }
    return ConnectionButtonTheme(
      idleColor: Color.lerp(idleColor, other.idleColor, t),
      connectedColor: Color.lerp(connectedColor, other.connectedColor, t),
    );
  }
}
