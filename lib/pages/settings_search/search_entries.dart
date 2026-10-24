import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/about/view.dart';
import 'package:PiliPlus/pages/backup/archive_setting.dart';
import 'package:PiliPlus/pages/backup/view.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/pages/font_setting.dart';
import 'package:PiliPlus/pages/webdav/view.dart';
import 'package:material_ui/material_ui.dart';

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    required this.category,
    this.subtitle,
    this.type,
    this.page,
    this.keywords = const [],
  });

  final String title;
  final String? subtitle;

  /// 所属分类，展示为面包屑
  final String category;

  /// 设置项所在分类，点击后跳到分类页并定位该项
  final SettingType? type;

  /// 不在分类列表里的入口项，点击后直接打开对应页面
  final Widget Function()? page;

  /// 不展示、只参与匹配的关键词
  final List<String> keywords;

  bool matches(String value) {
    final query = value.toLowerCase();
    return title.toLowerCase().contains(query) ||
        subtitle?.toLowerCase().contains(query) == true ||
        category.toLowerCase().contains(query) ||
        keywords.any((keyword) => keyword.toLowerCase().contains(query));
  }
}

List<SettingsSearchEntry> buildSettingsSearchEntries() {
  final entries = <SettingsSearchEntry>[];
  for (final type in SettingType.values) {
    final settings = _settingsOf(type);
    if (settings == null) continue;
    for (final item in settings) {
      entries.add(
        SettingsSearchEntry(
          title: item.effectiveTitle,
          subtitle: item.effectiveSubtitle,
          category: type.title,
          type: type,
        ),
      );
    }
  }
  entries.addAll(_entryOnlyEntries());
  return entries;
}

List<SettingsModel>? _settingsOf(SettingType type) {
  try {
    return type.settings;
  } on UnimplementedError {
    return null;
  }
}

List<SettingsSearchEntry> _entryOnlyEntries() => [
  SettingsSearchEntry(
    title: '关于',
    subtitle: '版本、更新、缓存与重置',
    category: '设置',
    type: SettingType.about,
    page: () => const AboutPage(),
  ),
  SettingsSearchEntry(
    title: '字体设置',
    subtitle: '打开字体设置页',
    category: '设置',
    page: () => const FontSettingPage(),
    keywords: const ['app字体设置', '字体大小', '字体粗细'],
  ),
  SettingsSearchEntry(
    title: '备份与恢复',
    subtitle: '备份、恢复与云端同步',
    category: '设置',
    type: SettingType.backupSetting,
    page: () => const BackupPage(),
    keywords: const ['webdav', '导出', '导入', '备份', '恢复', '云端'],
  ),
  SettingsSearchEntry(
    title: 'WebDAV 设置',
    category: '设置',
    page: () => const WebDavSettingPage(),
    keywords: const ['webdav', '加密', '密码', '压缩包'],
  ),
  SettingsSearchEntry(
    title: '压缩包设置',
    category: '设置',
    page: () => const ArchiveSettingPage(),
    keywords: const ['webdav', '加密', '密码', '压缩包'],
  ),
];
