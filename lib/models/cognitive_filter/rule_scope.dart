/// 规则作用的范围
enum RuleScope {
  danmaku('弹幕'),
  reply('评论'),
  dynamic('动态'),
  video('视频'),
  whisper('私信'),
  live('直播');

  const RuleScope(this.label);

  /// 界面显示的名称
  final String label;

  /// 由存储里的枚举名反查，未知名称返回 null
  static RuleScope? byName(String name) => values.asNameMap()[name];
}
