import 'package:PiliPlus/utils/backup/backup_method.dart';

/// 可备份的数据项
enum BackupItem {
  setting('设置', '所有可导出的设置项'),
  account('登录信息', '已登录账户的 cookie 信息等，属于敏感信息，慎重选择'),
  blacklist('黑名单', '已屏蔽的用户'),
  reply('历史评论', '已登录账户的评论（仅本机）'),
  search('搜索记录', '已登录账户的搜索历史（仅本机）'),
  customFont('自定义字体', '已导入的字体文件');

  const BackupItem(this.label, this.description);

  /// 界面显示的名称
  final String label;

  /// 界面显示的说明
  final String description;

  /// 默认勾选项
  static const Set<BackupItem> defaultSelected = {
    BackupItem.setting,
    BackupItem.blacklist,
    BackupItem.reply,
    BackupItem.search,
  };

  /// 被禁用项的说明
  static const String unsupportedTip = '目前选择的备份方式不支持备份此项目';

  /// 是否属于敏感信息
  bool get sensitive => this == BackupItem.account;

  /// 当前备份方式是否支持该项
  bool isSupportedBy(BackupMethod method) =>
      this != BackupItem.customFont || method != BackupMethod.clipboard;
}
