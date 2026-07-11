import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Логическое состояние монеты. Определяет палитру.
enum PinCoinState {
  idle,
  connecting,
  connected,
  error,
}

/// Плоские цвета для монеты — без градиентов.
/// Синтез visual-designer + color-psychologist (WCAG 2.2 audited).
class CoinPalette {
  const CoinPalette({
    required this.rim,
    required this.disk,
    required this.text,
    required this.glow,
    required this.glowBlur,
    required this.glowSpread,
    required this.glowAlpha,
    this.highlightAlpha = 0.35,
  });

  final Color rim;
  final Color disk;
  final Color text;
  final Color glow;
  final double glowBlur;
  final double glowSpread;
  final double glowAlpha;
  final double highlightAlpha;

  static CoinPalette lerp(CoinPalette a, CoinPalette b, double t) {
    return CoinPalette(
      rim: Color.lerp(a.rim, b.rim, t)!,
      disk: Color.lerp(a.disk, b.disk, t)!,
      text: Color.lerp(a.text, b.text, t)!,
      glow: Color.lerp(a.glow, b.glow, t)!,
      glowBlur: a.glowBlur + (b.glowBlur - a.glowBlur) * t,
      glowSpread: a.glowSpread + (b.glowSpread - a.glowSpread) * t,
      glowAlpha: a.glowAlpha + (b.glowAlpha - a.glowAlpha) * t,
      highlightAlpha: a.highlightAlpha + (b.highlightAlpha - a.highlightAlpha) * t,
    );
  }
}

// ─── Палитры состояний ──────────────────────────────────────
// connected: голубой обод (референс юзера) + charcoal + мокко PIN
const paletteConnected = CoinPalette(
  rim: Color(0xFF8FA8C4),   // dusty blue rim
  disk: Color(0xFF232120),  // charcoal
  text: Color(0xFFB08858),  // mocha (v3 brand)
  glow: Color(0xFF8FA8C4),
  glowBlur: 28,
  glowSpread: 1,
  glowAlpha: 0.40,
  highlightAlpha: 0.35,
);

// idle: mocha обод (WCAG fix vs #6E6E6E) + charcoal + приглушённый text
const paletteIdle = CoinPalette(
  rim: Color(0xFFB08858),   // mocha (не серый — тот FAIL WCAG)
  disk: Color(0xFF232120),
  text: Color(0xFFA0A0A0),  // subtle grey — «выключено, но живое»
  glow: Color(0xFFB08858),
  glowBlur: 20,
  glowSpread: 0,
  glowAlpha: 0.25,
  highlightAlpha: 0.25,
);

// connecting: амбер (не резкий жёлтый) — «жду»
const paletteConnecting = CoinPalette(
  rim: Color(0xFFD4B26A),   // amber (мягче #E5C468)
  disk: Color(0xFFB39555),  // disk-amber (немного темнее, сохраняет «монету»)
  text: Color(0xFF1A1917),  // near-black — max contrast
  glow: Color(0xFFD4B26A),
  glowBlur: 36,
  glowSpread: 3,
  glowAlpha: 0.45,
  highlightAlpha: 0.50,
);

// error: coral (мягче #DE5A50, РФ-friendly)
const paletteError = CoinPalette(
  rim: Color(0xFFD97865),   // coral
  disk: Color(0xFFA85846),  // disk-coral
  text: Color(0xFF1A1917),
  glow: Color(0xFFD97865),
  glowBlur: 32,
  glowSpread: 2,
  glowAlpha: 0.35,          // приглушить (не «кричит»)
  highlightAlpha: 0.35,
);

CoinPalette paletteFor(PinCoinState s) => switch (s) {
      PinCoinState.connected => paletteConnected,
      PinCoinState.connecting => paletteConnecting,
      PinCoinState.error => paletteError,
      PinCoinState.idle => paletteIdle,
    };

/// Плоская 3D-монета: обод + диск + текст «PIN». Плоские цвета,
/// тонкая highlight-дуга наверху для 3D-намёка.
class PinCoinPainter extends CustomPainter {
  const PinCoinPainter({
    required this.palette,
    required this.label,
    required this.fontFamily,
  });

  final CoinPalette palette;
  final String label;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final padding = side * 0.05;
    final outerR = side / 2 - padding;
    final innerR = outerR * 0.855; // тоньше обод (visual-designer)

    // 1. Внешний обод.
    canvas.drawCircle(center, outerR, Paint()..color = palette.rim);

    // 2. Внутренний диск.
    canvas.drawCircle(center, innerR, Paint()..color = palette.disk);

    // 3. Highlight-дуга (тонкий 3D-блик наверху).
    final arcRect = Rect.fromCircle(center: center, radius: outerR - side * 0.008);
    canvas.drawArc(
      arcRect,
      math.pi * 1.20,
      math.pi * 0.45,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: palette.highlightAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.006
        ..strokeCap = StrokeCap.round,
    );

    // 4. Текст «PIN» — плоский цвет, letter-spacing 2.0 для монетной гравировки.
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: fontFamily ?? 'Inter',
          fontSize: side * 0.26,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.0,
          height: 1.0,
          color: palette.text,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant PinCoinPainter old) =>
      old.palette != palette ||
      old.label != label ||
      old.fontFamily != fontFamily;
}
