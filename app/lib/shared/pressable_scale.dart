import 'package:flutter/material.dart';

import 'theme.dart';

/// Tap target with a subtle press-down scale + spring-back, no ripple.
///
/// Used across dashboard/insights cards for Google-style physical feedback.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressScale;
  final Duration duration;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressScale = 0.98,
    this.duration = Motion.fast,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scale = Tween<double>(begin: 1, end: widget.pressScale).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.elasticOut,
      ),
    );
  }

  @override
  void didUpdateWidget(PressableScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _controller.forward() : null,
        onTapCancel: enabled ? _controller.reverse : null,
        onTapUp: enabled ? (_) => _controller.reverse() : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}
