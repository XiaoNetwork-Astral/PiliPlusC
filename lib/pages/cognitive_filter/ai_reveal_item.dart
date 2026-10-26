import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/pages/backup/widgets/smooth_visibility.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:flutter/widgets.dart';

/// 经过 AI 判定的列表项：首次出现时先折叠，下一帧再带动画展开
///
/// 同一项滑出视野再回来不会重播；AI 屏蔽没启用时原样显示
class AiRevealItem extends StatefulWidget {
  const AiRevealItem({
    super.key,
    required this.surface,
    required this.item,
    required this.child,
  });

  final FilterSurface surface;

  /// 列表项对应的数据对象，用来记住它已经展开过
  final Object item;
  final Widget child;

  @override
  State<AiRevealItem> createState() => _AiRevealItemState();
}

class _AiRevealItemState extends State<AiRevealItem> {
  static final Expando<bool> _revealed = Expando<bool>('aiReveal');

  /// 创建时决定一次：不需要动画的项一直直接显示，不套动画容器
  late final bool _animate;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _animate =
        _revealed[widget.item] != true &&
        AiFilterRuntime.instance.isActiveFor(widget.surface);
    _visible = !_animate;
    if (_animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealed[widget.item] = true;
        setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return SmoothVisibility(visible: _visible, child: widget.child);
  }
}
