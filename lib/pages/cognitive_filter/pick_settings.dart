import 'package:PiliPlus/pages/setting/models/model.dart';

/// 按标题从现有设置列表中挑选设置项
///
/// 两个入口共用同一份数据，找不到标题时在 debug 下断言提醒
List<SettingsModel> pickSettings(
  List<SettingsModel> source,
  List<String> titles,
) {
  final byTitle = <String, SettingsModel>{};
  for (final item in source) {
    byTitle.putIfAbsent(item.effectiveTitle, () => item);
  }

  final result = <SettingsModel>[];
  for (final title in titles) {
    final item = byTitle[title];
    assert(item != null, '认知滤网未找到标题为「$title」的设置项');
    if (item != null) {
      result.add(item);
    }
  }
  return result;
}
