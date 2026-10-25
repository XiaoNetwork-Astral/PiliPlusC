import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/pages/backup/widgets/smooth_visibility.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 试判定：把一段文字交给 AI 判断，只看结果，不写入屏蔽历史
Future<void> showJudgeTrialDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _JudgeTrialDialog(),
  );
}

class _JudgeTrialDialog extends StatefulWidget {
  const _JudgeTrialDialog();

  @override
  State<_JudgeTrialDialog> createState() => _JudgeTrialDialogState();
}

class _JudgeTrialDialogState extends State<_JudgeTrialDialog> {
  final _textController = TextEditingController();
  final _contextController = TextEditingController();
  FilterSurface _surface = FilterSurface.danmaku;
  bool _judging = false;

  /// 最近一次成功的结果；再次判定时保留，新结果到了再带动画换掉
  JudgeVerdict? _verdict;
  String _category = '';

  @override
  void dispose() {
    _textController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _judge() async {
    final text = _textController.text.trim();
    if (_judging || text.isEmpty) return;
    setState(() => _judging = true);
    JudgeVerdict? verdict;
    try {
      verdict = await AiFilterRuntime.instance.trial(
        surface: _surface,
        text: text,
        context: _contextController.text.trim(),
      );
    } catch (_) {
      verdict = null;
    }
    if (!mounted) return;
    setState(() {
      _judging = false;
      if (verdict != null) {
        _verdict = verdict;
        _category = _categoryName(verdict.categoryId);
      }
    });
    if (verdict == null) {
      SmartDialog.showToast('AI 屏蔽未启用，或请求失败');
    }
  }

  String _categoryName(String? id) {
    if (id == null) return '';
    for (final item in CognitiveFilterConfig.effectiveCategories) {
      if (item.id == id) return item.name;
    }
    return '';
  }

  Widget _switching(String text, {Color? color}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Text(
        text,
        key: ValueKey(text),
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }

  Widget _buildResult(ThemeData theme) {
    final verdict = _verdict;
    final outline = theme.colorScheme.outline;
    final score = verdict?.score ?? 0;
    return SmoothVisibility(
      visible: verdict != null,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CfTile(
              icon: Icons.fact_check_outlined,
              title: '结果',
              subtitleWidget: _switching(
                verdict?.blocked ?? false ? '会被屏蔽' : '不会屏蔽',
                color: outline,
              ),
            ),
            SmoothVisibility(
              visible: _category.isNotEmpty,
              child: CfTile(
                icon: Icons.category_outlined,
                title: '可能属于',
                subtitleWidget: _switching(_category, color: outline),
              ),
            ),
            CfTile(
              icon: Icons.percent,
              title: '得分',
              subtitleWidget: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: score),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(fontSize: 12, color: outline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('试判定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final surface in FilterSurface.values)
                  ChoiceChip(
                    label: Text(surface.label),
                    selected: _surface == surface,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _surface = surface),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '文本',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contextController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '背景（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            _buildResult(theme),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '关闭',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        FilledButton.tonal(
          onPressed: _judging ? null : _judge,
          child: _judging
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('判定'),
        ),
      ],
    );
  }
}
