/// 弹幕 AI 判定使用的视频背景
class DanmakuJudgeContext {
  const DanmakuJudgeContext({
    required this.title,
    required this.partition,
  });

  /// 视频标题
  final String Function() title;

  /// 分区名，可能为空
  final String Function() partition;
}
