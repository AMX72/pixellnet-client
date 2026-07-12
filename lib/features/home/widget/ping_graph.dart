import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// v0.1.29: живой график скорости (или ping) за последние 60 секунд.
///
/// Ring-буфер [_values] обновляется каждую секунду. Painter отрисовывает
/// плавную линию + fill-градиент. Используется в session sheet.
class PingGraph extends ConsumerStatefulWidget {
  const PingGraph({
    super.key,
    this.metric = PingMetric.downSpeed,
    this.height = 96,
  });

  final PingMetric metric;
  final double height;

  @override
  ConsumerState<PingGraph> createState() => _PingGraphState();
}

enum PingMetric { ping, upSpeed, downSpeed }

class _PingGraphState extends ConsumerState<PingGraph> {
  static const _capacity = 60; // 60 секунд истории
  final List<double> _values = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final v = _readValue();
      setState(() {
        _values.add(v);
        if (_values.length > _capacity) _values.removeAt(0);
      });
    });
    // Пре-заполняем 0-ями чтобы график сразу растягивался на всю ширину
    for (int i = 0; i < _capacity; i++) {
      _values.add(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double _readValue() {
    switch (widget.metric) {
      case PingMetric.ping:
        final active = ref.read(activeProxyNotifierProvider).valueOrNull;
        final d = active?.urlTestDelay ?? 0;
        return d > 0 && d < 65000 ? d.toDouble() : 0;
      case PingMetric.upSpeed:
        final stats = ref.read(statsNotifierProvider).valueOrNull;
        return (stats?.uplink.toInt() ?? 0).toDouble();
      case PingMetric.downSpeed:
        final stats = ref.read(statsNotifierProvider).valueOrNull;
        return (stats?.downlink.toInt() ?? 0).toDouble();
    }
  }

  Color _colorFor() => switch (widget.metric) {
        PingMetric.ping => PixellnetBrand.amber,
        PingMetric.upSpeed => PixellnetBrand.blue,
        PingMetric.downSpeed => PixellnetBrand.olive,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: _GraphPainter(
          values: List.of(_values),
          color: _colorFor(),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(1, math.max);
    final w = size.width;
    final h = size.height;
    final step = w / (values.length - 1).clamp(1, values.length);

    // Fill-path (под линией)
    final fillPath = Path()..moveTo(0, h);
    // Stroke-path (линия)
    final strokePath = Path();

    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final norm = maxV > 0 ? (values[i] / maxV).clamp(0.0, 1.0) : 0.0;
      final y = h - norm * (h - 4) - 2; // 2dp padding сверху и снизу
      if (i == 0) {
        strokePath.moveTo(x, y);
      } else {
        strokePath.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }
    fillPath
      ..lineTo(w, h)
      ..close();

    // Заливка
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Линия
    canvas.drawPath(
      strokePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Тонкая ось снизу
    canvas.drawLine(
      Offset(0, h - 0.5),
      Offset(w, h - 0.5),
      Paint()
        ..color = color.withValues(alpha: 0.20)
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      old.values != values || old.color != color;
}
