import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 列表等待 AI 判定时，在屏幕顶部显示的提示，让人知道在等什么
///
/// 持续不到 [_showDelay] 的判定（比如命中缓存）不会显示，避免闪一下；
/// 判定结束后再停留 [_hideDelay]，列表分几次判定时提示不会反复滑出滑入
class AiBusyIndicator extends StatefulWidget {
  const AiBusyIndicator({super.key});

  @override
  State<AiBusyIndicator> createState() => _AiBusyIndicatorState();
}

class _AiBusyIndicatorState extends State<AiBusyIndicator>
    with SingleTickerProviderStateMixin {
  static const Duration _showDelay = Duration(milliseconds: 300);
  static const Duration _hideDelay = Duration(milliseconds: 900);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final ValueNotifier<int> _busy = AiFilterRuntime.instance.busy;
  Timer? _timer;
  Timer? _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _busy.addListener(_onBusyChanged);
    _onBusyChanged();
  }

  void _onBusyChanged() {
    if (_busy.value > 0) {
      _hideTimer?.cancel();
      if (_visible || (_timer?.isActive ?? false)) return;
      _timer = Timer(_showDelay, () {
        if (!mounted || _busy.value <= 0) return;
        _pulse.repeat(reverse: true);
        setState(() => _visible = true);
      });
    } else {
      _timer?.cancel();
      if (!_visible) return;
      _hideTimer?.cancel();
      _hideTimer = Timer(_hideDelay, () {
        if (!mounted || _busy.value > 0) return;
        _pulse.stop();
        setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _busy.removeListener(_onBusyChanged);
    _timer?.cancel();
    _hideTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 全屏播放时弹幕区已有自己的提示，这里不再显示
    final player = PlPlayerController.instance;
    if (player == null) return _buildPill(context, false);
    return Obx(() => _buildPill(context, player.isFullScreen.value));
  }

  Widget _buildPill(BuildContext context, bool fullScreen) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top + 10;
    final show = _visible && !fullScreen;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, -2.5),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: Tween<double>(
                          begin: 0.35,
                          end: 1,
                        ).animate(_pulse),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.85,
                            end: 1.1,
                          ).animate(_pulse),
                          child: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI 判定中',
                        style: TextStyle(
                          fontSize: 13,
                          decoration: TextDecoration.none,
                          fontWeight: FontWeight.normal,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
