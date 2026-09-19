import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Static ambient aurora behind the shell pages.
///
/// Previously three infinitely-animated gradient bars with large blur
/// shadows, which re-rasterized the blur every frame underneath translucent
/// cards — the single largest source of dropped frames in the app.
///
/// The same visual is now painted once by a [CustomPainter]: gradient-only
/// bands (no blur filters, no animation). Wrapped in a [RepaintBoundary] it
/// rasterizes exactly once per theme/size change and never again, so idle
/// frames cost nothing.
class NeonRibbonBackground extends StatelessWidget {
  const NeonRibbonBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark
        ? const [Color(0xFFE84545), Color(0xFF5E5CE6), Color(0xFF34C759)]
        : const [Color(0xFF0066CC), Color(0xFFD1E9FF), Color(0xFFFF9500)];

    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _AuroraPainter(colors: colors)),
          ),
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.colors});

  final List<Color> colors;

  static const _centers = [
    Offset(50, 125),
    Offset(50, 325),
    Offset(50, 525),
  ];

  static const _bandLength = 500.0;

  /// Concentric bands per ribbon: a core streak plus two wider, fainter
  /// layers that fake the soft glow of the old blur shadow. Every band uses
  /// an end-to-end gradient so there are no hard edges anywhere.
  static const _bands = [
    (halfHeight: 25.0, peak: 0.30),
    (halfHeight: 45.0, peak: 0.10),
    (halfHeight: 70.0, peak: 0.04),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < colors.length; i++) {
      final color = colors[i];
      final center = _centers[i];

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-math.pi / 4);

      for (final band in _bands) {
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: _bandLength,
          height: band.halfHeight * 2,
        );
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: band.peak),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect);
        canvas.drawRect(rect, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) =>
      !listEquals(oldDelegate.colors, colors);
}