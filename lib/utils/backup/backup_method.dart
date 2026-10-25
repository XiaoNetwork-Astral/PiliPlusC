/// 备份方式
enum BackupMethod {
  webdav('WebDAV', '上传到 WebDAV 服务器'),
  archive('压缩包', '保存为本地压缩包文件'),
  clipboard('剪贴板', '编码后复制到剪贴板'),
  cloud('B 站云端同步', '与 B 站账号互相同步部分屏蔽数据，完整备份请使用其它方式');

  const BackupMethod(this.label, this.description);

  /// 界面显示的名称
  final String label;

  /// 界面显示的说明
  final String description;

  /// 是否支持备份自定义字体
  bool get supportsCustomFont =>
      this != BackupMethod.clipboard && this != BackupMethod.cloud;

  /// 是否有配置页
  bool get configurable =>
      this != BackupMethod.clipboard && this != BackupMethod.cloud;
}
