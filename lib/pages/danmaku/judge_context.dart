/// 弹幕 AI 判定使用的视频背景
class DanmakuJudgeContext {
  const DanmakuJudgeContext({
    required this.title,
    required this.partition,
    this.source,
  });

  /// 视频标题
  final String Function() title;

  /// 分区名，可能为空
  final String Function() partition;

  /// 能定位到这个视频的信息（bvid、aid、videoType、epId、seasonId），用于屏蔽历史里回看原片段
  final Map<String, dynamic> Function()? source;
}
