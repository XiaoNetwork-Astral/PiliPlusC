import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:flutter/foundation.dart';

/// 规则列表的数据源
///
/// 屏蔽规则与 AI 白名单共用同一套列表页与编辑页；页面只依赖这个接口，
/// 不关心数据实际存在设置、`blackMids` 还是别的地方。
abstract class RuleSource {
  /// 当前的全部规则
  List<FilterRule> get rules;

  /// 任何改动都会自增，供编译缓存失效与界面刷新
  ValueNotifier<int> get version;

  /// 添加一条规则，校验由实现负责
  void add(FilterRule rule);

  /// 按 id 更新规则
  void update(FilterRule rule);

  /// 按 id 删除规则
  void remove(String id);

  /// 按 id 启停规则
  void setEnabled(String id, bool enabled);
}
