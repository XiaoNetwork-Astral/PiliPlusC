import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';

/// 对列表做 AI 判定，返回未被屏蔽的项；未启用、失败或超时一律原样返回
Future<List<T>> aiFilterList<T>({
  required FilterSurface surface,
  required List<T> items,
  required String Function(T item) textOf,
  int? Function(T item)? midOf,
  Map<String, dynamic>? Function(T item)? metaOf,
  Map<String, dynamic>? Function(T item)? snapshotOf,
  String title = '',
  String context = '',
}) async {
  try {
    if (items.isEmpty || !AiFilterRuntime.instance.isActiveFor(surface)) {
      return items;
    }
    // 全屏时评论与相关视频用户看不到，暂不送 AI，退出全屏后由视频页补判。
    // 弹幕在全屏里可见，动态/直播不受影响。
    final playerController = PlPlayerController.instance;
    if (playerController != null &&
        playerController.isFullScreen.value &&
        (surface == FilterSurface.reply || surface == FilterSurface.video)) {
      AiFilterRuntime.instance.deferredWhileFullscreen = true;
      return items;
    }
    final judgeItems = <JudgeItem>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final text = textOf(item);
      // 空文本不送判定，直接保留
      if (text.isNotEmpty) {
        judgeItems.add(
          JudgeItem(
            id: '$i',
            text: text,
            mid: midOf?.call(item),
            meta: metaOf?.call(item),
            snapshotBuilder: snapshotOf == null
                ? null
                : () => snapshotOf(item) ?? const <String, dynamic>{},
          ),
        );
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
