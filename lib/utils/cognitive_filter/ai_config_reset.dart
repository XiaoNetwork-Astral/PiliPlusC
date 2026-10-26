import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';

/// 一次性重置 AI 屏蔽配置
///
/// 这一版重做了类别、门槛与整理接口的设置，内测期间留下的旧值会让新默认值
/// 不生效，所以升级到这一版时把它们清掉一次，之后不再执行。
/// 接口地址、密钥、代理、白名单和不外传规则不动。
abstract final class AiConfigReset {
  /// 本次重置的版本号，改它就会再重置一次
  static const int version = 1;

  static const String _doneKey = 'cfAiConfigResetVersion';

  static const List<String> _keys = <String>[
    SettingBoxKey.cfProThreshold,
    SettingBoxKey.cfCategoryOverrides,
    SettingBoxKey.cfCustomCategories,
    SettingBoxKey.cfAiThresholdDelta,
    SettingBoxKey.cfAiSurfaces,
    SettingBoxKey.cfAiDailyCapUsd,
    SettingBoxKey.cfApiTimeout,
    SettingBoxKey.cfLlmDailyCapCny,
    SettingBoxKey.cfLlmTimeout,
    SettingBoxKey.cfLlmOutputRetries,
    SettingBoxKey.cfLlmOtherRetries,
  ];

  static void runIfNeeded() {
    final box = GStorage.setting;
    final done = box.get(_doneKey);
    if (done is int && done >= version) return;
    for (final key in _keys) {
      box.delete(key);
    }
    box.put(_doneKey, version);
  }
}
