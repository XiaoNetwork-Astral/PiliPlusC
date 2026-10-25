/// 认知滤网的适用面
enum FilterSurface {
  danmaku('弹幕', '弹幕'),
  reply('评论', '评论'),
  dynamic('动态', '动态'),
  video('视频', '视频');

  const FilterSurface(this.label, this.objectName);

  /// 界面显示的名称
  final String label;

  /// 发请求时题面前缀里的对象名，如「只判断【弹幕】这一条」
  final String objectName;
}
