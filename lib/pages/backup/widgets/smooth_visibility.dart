import 'package:material_ui/material_ui.dart';

/// 展开与收起都有动画的显示容器，收起结束前内容不会被移除
class SmoothVisibility extends StatefulWidget {
  const SmoothVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
  });

  final bool visible;
  final Widget child;
  final Duration duration;

  @override
  State<SmoothVisibility> createState() => _SmoothVisibilityState();
}

class _SmoothVisibilityState extends State<SmoothVisibility>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.visible ? 1 : 0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(SmoothVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        if (_controller.isDismissed) {
          return const SizedBox(width: double.infinity);
        }
        return SizeTransition(
          sizeFactor: _animation,
          axisAlignment: -1,
          child: FadeTransition(opacity: _animation, child: child),
        );
      },
      child: widget.child,
    );
  }
}
