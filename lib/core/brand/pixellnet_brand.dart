import 'package:flutter/material.dart';

/// PIXELLNET brand tokens — Material 3 Dark (AI Studio aesthetic) v5, 2026-11-11.
///
/// Dark primary: bg #131314 near-black, surface #1E1F20, accent #8AB4F8
/// (Google Material Dynamic blue). Table-row layout, hairline dividers,
/// zero cards with borders. Light secondary (auto-follow system) — AI Studio Light.
abstract class PixellnetBrand {
  static const String appName = 'PIXELLNET';
  static const String appTagline = 'Стабильное соединение в один клик';
  static const String homepage = 'https://pixellnet.com';
  static const String supportEmail = 'support@pixellnet.com';

  // ─── Dark palette (primary) ───
  static const Color bgScaffold = Color(0xFF131314);
  static const Color bgSurface = Color(0xFF1E1F20);
  static const Color bgElevated = Color(0xFF2A2B2D);

  static const Color textPrimary = Color(0xFFE3E3E3);
  static const Color textSecondary = Color(0xFF9AA0A6);
  static const Color textMuted = Color(0xFF737377);

  static const Color accent = Color(0xFF8AB4F8);
  static const Color accentHover = Color(0xFFA8C7FA);
  static const Color accentBg = Color(0x1F8AB4F8); // 12% alpha chip bg

  static const Color success = Color(0xFF81C995);
  static const Color warning = Color(0xFFFDD663);
  static const Color error = Color(0xFFF28B82);

  static const Color dividerHairline = Color(0x14FFFFFF); // ~8% white
  static const Color dividerStrong = Color(0xFF3C4043);

  // ─── Light palette (secondary, auto-follow system) — AI Studio Light ───
  static const Color bgScaffoldLight = Color(0xFFFFFFFF);
  static const Color bgSurfaceLight = Color(0xFFF8F9FA);
  static const Color bgElevatedLight = Color(0xFFF1F3F4);

  static const Color textPrimaryLight = Color(0xFF202124);
  static const Color textSecondaryLight = Color(0xFF5F6368);
  static const Color textMutedLight = Color(0xFF80868B);

  static const Color accentLight = Color(0xFF1A73E8);
  static const Color accentHoverLight = Color(0xFF1765CC);
  static const Color accentBgLight = Color(0xFFE8F0FE);

  static const Color successLight = Color(0xFF1E8E3E);
  static const Color warningLight = Color(0xFFB06000);
  static const Color errorLight = Color(0xFFC5221F);

  static const Color dividerHairlineLight = Color(0xFFE8EAED);
  static const Color dividerStrongLight = Color(0xFFDADCE0);

  // ─── Backward-compat aliases (чтоб старый код не ломался) ───
  static const Color mocha = accent;
  static const Color mochaOnDark = accent;
  static const Color mochaDark = accentHover;
  static const Color amber = warning;
  static const Color olive = success;
  static const Color coral = error;
  static const Color coralOnDark = error;
  static const Color blue = accent;
  static const Color primary = accent;
  static const Color bgDark = bgScaffold;
  static const Color surface = bgSurface;
  static const Color surfaceElevated = bgElevated;
  static const Color surfaceHover = bgElevated;
  static const Color textOnDark = textPrimary;
}
