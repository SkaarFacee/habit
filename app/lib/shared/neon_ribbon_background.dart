import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math';

// Neon Ribbon background widget
class NeonRibbonBackground extends StatelessWidget {
  const NeonRibbonBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark
        ? [const Color(0xFFE84545), const Color(0xFF5E5CE6), const Color(0xFF34C759)]
        : [const Color(0xFF0066CC), const Color(0xFFD1E9FF), const Color(0xFFFF9500)];

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        ...List.generate(3, (index) {
          return Positioned(
            top: (index * 200) + 100,
            left: -200,
            child: Animate(
              onPlay: (controller) => controller.repeat(reverse: true),
              effects: [
                MoveEffect(
                  duration: (5 + index * 2).seconds,
                  begin: const Offset(-50, 0),
                  end: const Offset(50, 0),
                  curve: Curves.easeInOutSine,
                ),
              ],
              child: Transform.rotate(
                angle: -pi / 4,
                child: Container(
                  width: 500,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colors[index].withOpacity(0), colors[index].withOpacity(0.3), colors[index].withOpacity(0)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors[index].withOpacity(0.4),
                        blurRadius: 50,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}