import 'package:flutter/material.dart';

abstract class PixellnetBrand {
  static const String appName = 'PIXELLNET';
  static const String appTagline = 'Один тап — и ты в сети';
  static const String homepage = 'https://pixellnet.com';
  static const String supportEmail = 'support@pixellnet.com';

  // ─── Palette v3 (warm charcoal + mocha) ───
  // Обоснование выбора и WCAG-контрасты — см. docs/knowledge-palette-v3-wcag.md

  // Backgrounds
  static const Color bgDark = Color(0xFF1A1917); // near-black для scaffold
  static const Color surface = Color(0xFF2B2A28); // warm charcoal
  static const Color surfaceElevated = Color(0xFF302F2C); // card bg
  static const Color surfaceHover = Color(0xFF38352F);

  // Brand
  static const Color mocha = Color(0xFFB08858); // fills / buttons / logo tint
  static const Color mochaOnDark = Color(0xFFC9A075); // текст на dark (WCAG AA fix)
  static const Color mochaDark = Color(0xFF9A7548); // pressed state

  // Accents (semantic)
  static const Color amber = Color(0xFFD4B26A); // connecting / loading / trial
  static const Color olive = Color(0xFF8FA05A); // connected / success
  static const Color coral = Color(0xFFD97865); // error fill
  static const Color coralOnDark = Color(0xFFE89380); // error text (WCAG)
  static const Color blue = Color(0xFF8FA8C4); // links / info

  // Text
  static const Color textPrimary = Color(0xFFE7E1D6); // beige, contrast 10.4:1
  static const Color textSecondary = Color(0xFFA8A5A0); // muted
  static const Color textMuted = Color(0xFF7A7773);

  // Backwards-compat aliases (для существующего кода)
  static const Color primary = mocha;
  static const Color accent = amber;
  static const Color textOnDark = textPrimary;
}
