/// 备份与恢复的统一异常
///
/// [message] 是可直接展示给用户的中文原因，页面无需再次拼接前缀
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 压缩包已加密，但没有提供密码
class BackupPasswordRequiredException extends BackupException {
  const BackupPasswordRequiredException() : super('需要密码');
}

/// 提供了密码，但压缩包密码错误
class BackupPasswordWrongException extends BackupException {
  const BackupPasswordWrongException() : super('密码错误');
}

/// 没有勾选任何备份项
class BackupSelectionEmptyException extends BackupException {
  const BackupSelectionEmptyException() : super('请至少勾选一项');
}

/// WebDAV 尚未配置
class BackupNotConfiguredException extends BackupException {
  const BackupNotConfiguredException() : super('请先配置 WebDAV');
}

/// WebDAV 上没有备份文件
class BackupNoBackupException extends BackupException {
  const BackupNoBackupException() : super('WebDAV 上没有备份文件');
}

/// 剪贴板没有数据
class BackupClipboardEmptyException extends BackupException {
  const BackupClipboardEmptyException() : super('剪贴板无数据');
}

/// 用户取消了文件选择或保存
class BackupCancelledException extends BackupException {
  const BackupCancelledException() : super('已取消');
}

/// 解析备份数据失败
class BackupParseException extends BackupException {
  BackupParseException(String reason) : super('解析失败：$reason');
}
