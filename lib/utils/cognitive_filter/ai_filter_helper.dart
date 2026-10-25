import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';

/// 对列表做 AI 判定，返回未被屏蔽的项；未启用、失败或超时一律原样返回
Future<List<T>> aiFilterList<T>({
  required FilterSurface surface,
  required List<T> items,
  required String Function(T item) textOf,
  String title = '',
  String context = '',
}) async {
  try {
    if (items.isEmpty || !AiFilterRuntime.instance.isActiveFor(surface)) {
      return items;
    }
    final judgeItems = <JudgeItem>[];
    for (var i = 0; i < items.length; i++) {
      final text = textOf(items[i]);
      // 空文本不送判定，直接保留
      if (text.isNotEmpty) {
        judgeItems.add(JudgeItem(id: '$i', text: text));
      }
    }
    if (judgeItems.isEmpty) {
      return items;
    }
    final result = await AiFilterRuntime.instance.judge(
      surface: surface,
      items: judgeItems,
      title: title,
      context: context,
    );
    if (result == null) {
      return items;
    }
    final filtered = <T>[];
    for (var i = 0; i < items.length; i++) {
      final verdict = result.verdicts['$i'];
      if (verdict == null || !verdict.blocked) {
        filtered.add(items[i]);
      }
    }
    return filtered;
  } catch (_) {
    // 判定异常时整批放行
    return items;
  }
}
