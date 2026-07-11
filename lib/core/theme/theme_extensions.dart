import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';

class ConnectionButtonTheme extends ThemeExtension<ConnectionButtonTheme> {
  const ConnectionButtonTheme({
    this.idleColor,
    this.connectingColor,
    this.connectedColor,
    this.errorColor,
    this.textColor,
  });

  final Color? idleColor;
  final Color? connectingColor;
  final Color? connectedColor;
  final Color? errorColor;
  final Color? textColor;

  static const ConnectionButtonTheme light = ConnectionButtonTheme(
    idleColor: PixellnetBrand.mocha,
    connectingColor: PixellnetBrand.amber,
    connectedColor: PixellnetBrand.olive,
    errorColor: PixellnetBrand.coral,
    textColor: Color(0xFF1A1917),
  );

  @override
  ThemeExtension<ConnectionButtonTheme> copyWith({
    Color? idleColor,
    Color? connectingColor,
    Color? connectedColor,
    Color? errorColor,
    Color? textColor,
  }) => ConnectionButtonTheme(
    idleColor: idleColor ?? this.idleColor,
    connectingColor: connectingColor ?? this.connectingColor,
    connectedColor: connectedColor ?? this.connectedColor,
    errorColor: errorColor ?? this.errorColor,
    textColor: textColor ?? this.textColor,
  );

  @override
  ThemeExtension<ConnectionButtonTheme> lerp(covariant ThemeExtension<ConnectionButtonTheme>? other, double t) {
    if (other is! ConnectionButtonTheme) {
      return this;
    }
    return ConnectionButtonTheme(
      idleColor: Color.lerp(idleColor, other.idleColor, t),
      connectingColor: Color.lerp(connectingColor, other.connectingColor, t),
      connectedColor: Color.lerp(connectedColor, other.connectedColor, t),
      errorColor: Color.lerp(errorColor, other.errorColor, t),
      textColor: Color.lerp(textColor, other.textColor, t),
    );
  }
}
