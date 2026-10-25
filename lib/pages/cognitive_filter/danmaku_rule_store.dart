import 'package:PiliPlus/http/danmaku_block.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dm_block_type.dart';
import 'package:PiliPlus/models/user/danmaku_block.dart';
import 'package:PiliPlus/models/user/danmaku_rule.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 云端同步前的差异，用于让用户确认
class DanmakuSyncPlan {
  const DanmakuSyncPlan({required this.toAdd, required this.toDelete});

  /// 云端缺少、需要添加的规则，按类型存放
  final Map<DmBlockType, List<String>> toAdd;

  /// 云端多出、需要删除的规则，按类型存放，值为云端规则 id 与内容
  final Map<DmBlockType, List<SimpleRule>> toDelete;

  int get addCount => toAdd.values.fold(0, (sum, list) => sum + list.length);

  int get deleteCount =>
      toDelete.values.fold(0, (sum, list) => sum + list.length);

  bool get isEmpty => addCount == 0 && deleteCount == 0;
}

/// 弹幕屏蔽规则的本地副本
///
/// 规则先在本地编辑并立即生效，需要时再手动与 B 站云端同步
abstract final class DanmakuRuleStore {
  static final _slashed = RegExp(r'^/(.*)/$');

  static RuleFilter get _filter =>
      PlPlayerController.instance?.filters ?? Pref.danmakuFilterRule;

  /// 某类规则的当前内容
  static List<String> items(DmBlockType type) {
    final filter = _filter;
    return switch (type) {
      DmBlockType.keyword => List<String>.of(filter.dmFilterString),
      DmBlockType.regex => [for (final i in filter.dmRegExp) i.pattern],
      DmBlockType.uid => List<String>.of(filter.dmUid),
    };
  }

  static int count(DmBlockType type) => items(type).length;

  /// 校验并添加，返回错误说明，成功返回 null
  static String? add(DmBlockType type, String value) {
    final error = _check(type, value);
    if (error != null) return error;
    final list = items(type);
    if (list.contains(value)) return '这条规则已经存在';
    _save(type, [...list, value]);
    return null;
  }

  /// 校验并替换，返回错误说明，成功返回 null
  static String? update(DmBlockType type, String oldValue, String value) {
    final error = _check(type, value);
    if (error != null) return error;
    final list = items(type);
    if (value != oldValue && list.contains(value)) return '这条规则已经存在';
    _save(type, [for (final i in list) i == oldValue ? value : i]);
    return null;
  }

  static void remove(DmBlockType type, String value) {
    _save(type, items(type).where((i) => i != value).toList());
  }

  static String? _check(DmBlockType type, String value) {
    if (value.trim().isEmpty) return '内容不能为空';
    if (type == DmBlockType.regex) {
      try {
        RegExp(value, caseSensitive: false);
      } on FormatException {
        return '正则表达式不正确';
      }
    }
    return null;
  }

  static void _save(DmBlockType type, List<String> values) {
    final current = _filter;
    _saveFilter(
      RuleFilter(
        type == DmBlockType.keyword ? values : current.dmFilterString,
        type == DmBlockType.regex
            ? [for (final i in values) RegExp(i, caseSensitive: false)]
            : current.dmRegExp,
        type == DmBlockType.uid ? values.toSet() : current.dmUid,
      ),
    );
  }

  static void _saveFilter(RuleFilter filter) {
    GStorage.localCache.put(LocalCacheKey.danmakuFilterRules, filter);
    PlPlayerController.instance?.filters = filter;
  }

  static String _normalize(DmBlockType type, String filter) => type ==
          DmBlockType.regex
      ? (_slashed.matchAsPrefix(filter)?.group(1) ?? filter)
      : filter;

  /// 读取云端规则，失败返回 null 并提示原因
  static Future<DanmakuBlockDataModel?> _fetchCloud() async {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('请先登录');
      return null;
    }
    final result = await DanmakuFilterHttp.danmakuFilter();
    if (result case Success(:final response)) return response;
    result.toast();
    return null;
  }

  /// 用云端规则覆盖本地，返回是否成功
  static Future<bool> pull() async {
    final cloud = await _fetchCloud();
    if (cloud == null) return false;
    _saveFilter(
      RuleFilter.fromRuleTypeEntries([cloud.rule, cloud.rule1, cloud.rule2]),
    );
    return true;
  }

  /// 比较本地与云端，得出上传所需的改动
  static Future<DanmakuSyncPlan?> planPush() async {
    final cloud = await _fetchCloud();
    if (cloud == null) return null;
    final cloudRules = [cloud.rule, cloud.rule1, cloud.rule2];
    final toAdd = <DmBlockType, List<String>>{};
    final toDelete = <DmBlockType, List<SimpleRule>>{};
    for (final type in DmBlockType.values) {
      final local = items(type).toSet();
      final remote = {
        for (final rule in cloudRules[type.index])
          _normalize(type, rule.filter): rule,
      };
      toAdd[type] = local.where((i) => !remote.containsKey(i)).toList();
      toDelete[type] = [
        for (final entry in remote.entries)
          if (!local.contains(entry.key)) entry.value,
      ];
    }
    return DanmakuSyncPlan(toAdd: toAdd, toDelete: toDelete);
  }

  /// 执行上传，返回失败条数
  static Future<int> pushPlan(DanmakuSyncPlan plan) async {
    var failed = 0;
    for (final entry in plan.toDelete.entries) {
      for (final rule in entry.value) {
        final res = await DanmakuFilterHttp.danmakuFilterDel(ids: rule.id);
        if (!res.isSuccess) failed++;
      }
    }
    for (final entry in plan.toAdd.entries) {
      for (final filter in entry.value) {
        final res = await DanmakuFilterHttp.danmakuFilterAdd(
          filter: filter,
          type: entry.key.index,
        );
        if (!res.isSuccess) failed++;
      }
    }
    return failed;
  }
}
