import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/about/view.dart';
import 'package:PiliPlus/pages/backup/archive_setting.dart';
import 'package:PiliPlus/pages/backup/view.dart';
import 'package:PiliPlus/pages/cognitive_filter/danmaku_block_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/provider_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_list_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_sub_pages.dart';
import 'package:PiliPlus/pages/cognitive_filter/view.dart';
import 'package:PiliPlus/pages/setting/models/dyn_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/reply_settings.dart';
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
  entries
    ..addAll(_entryOnlyEntries())
    ..addAll(_filterEntries());
  return entries;
}

/// 认知滤网里的设置项，它们不在 [SettingType] 的列表里，搜索时直接打开所在页面
List<SettingsSearchEntry> _filterEntries() {
  Iterable<SettingsSearchEntry> from(
    List<SettingsModel> settings,
    String category,
    Widget Function() page,
  ) => settings.map(
    (item) => SettingsSearchEntry(
      title: item.effectiveTitle,
      subtitle: item.effectiveSubtitle,
      category: category,
      page: page,
    ),
  );
  return [
    SettingsSearchEntry(
      title: '规则',
      subtitle: '关键词、正则、分区与用户规则',
      category: '认知滤网',
      page: () => const RuleListPage(),
      keywords: const ['屏蔽', '过滤', '关键词', '正则', '黑名单', '分区'],
    ),
    SettingsSearchEntry(
      title: '弹幕屏蔽',
      subtitle: '智能云屏蔽等级、按类型屏蔽',
      category: '认知滤网',
      page: () => const DanmakuBlockSubPage(),
      keywords: const ['屏蔽等级', '滚动', '顶部', '底部', '彩色', '高级'],
    ),
    ...from(replyBlockSettings, '认知滤网 评论屏蔽', () => const ReplyRuleSubPage()),
    ...from(dynBlockSettings, '认知滤网 动态屏蔽', () => const DynRuleSubPage()),
    ...from(videoBlockSettings, '认知滤网 视频屏蔽', () => const VideoRuleSubPage()),
  ];
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
    title: '认知滤网',
    subtitle: '规则屏蔽、AI 屏蔽、屏蔽统计与类别规则',
    category: '设置',
    type: SettingType.cognitiveFilter,
    page: () => const CognitiveFilterPage(),
    keywords: const ['屏蔽', '过滤', 'ai', 'jev', '统计', '类别规则'],
  ),
  SettingsSearchEntry(
    title: 'AI 提供商',
    subtitle: '接口地址、API Key、模型名与等待超时',
    category: '认知滤网',
    page: () => const FilterProviderPage(),
    keywords: const ['jev', 'api key', '密钥', '接口', '测试连接'],
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
