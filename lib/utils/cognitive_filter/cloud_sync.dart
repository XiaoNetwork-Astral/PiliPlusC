import 'package:PiliPlus/grpc/im.dart';
import 'package:PiliPlus/http/black.dart';
import 'package:PiliPlus/http/danmaku_block.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/models/user/danmaku_block.dart';
import 'package:PiliPlus/models_new/blacklist/data.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/backup/backup_exception.dart';
import 'package:PiliPlus/utils/cognitive_filter/cloud_sync_plan.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:PiliPlus/utils/global_data.dart';

export 'package:PiliPlus/utils/cognitive_filter/cloud_sync_plan.dart';

/// 屏蔽数据与 B 站云端的非破坏性同步
///
/// 上传只补云端缺少的项，下载只补本地缺少的项，两边都不删除已有数据。
abstract final class CloudSync {
  static const Duration _blacklistInterval = Duration(milliseconds: 300);

  /// 上传所选项
  static Future<CloudSyncReport> push(Iterable<CloudSyncKind> kinds) =>
      _run(kinds, _pushOne);

  /// 下载并合并所选项
  static Future<CloudSyncReport> pull(Iterable<CloudSyncKind> kinds) =>
      _run(kinds, _pullOne);

  static Future<CloudSyncResult> _pushOne(CloudSyncKind kind) => switch (kind) {
    CloudSyncKind.danmakuRules => pushDanmaku(),
    CloudSyncKind.whisperRules => pushWhisper(),
    CloudSyncKind.blacklist => pushBlacklist(),
  };

  static Future<CloudSyncResult> _pullOne(CloudSyncKind kind) => switch (kind) {
    CloudSyncKind.danmakuRules => pullDanmaku(),
    CloudSyncKind.whisperRules => pullWhisper(),
    CloudSyncKind.blacklist => pullBlacklist(),
  };

  static Future<CloudSyncReport> _run(
    Iterable<CloudSyncKind> kinds,
    Future<CloudSyncResult> Function(CloudSyncKind) action,
  ) async {
    if (!Accounts.main.isLogin) {
      throw const BackupException('同步屏蔽数据需要先登录账号，请登录后重试');
    }
    final results = <CloudSyncKind, CloudSyncResult>{};
    for (final kind in kinds) {
      try {
        results[kind] = await action(kind);
      } on BackupException catch (e) {
        results[kind] = CloudSyncResult(failed: 1, note: e.message);
      } catch (_) {
        // 不拼接原始异常，避免请求头等信息进入界面
        results[kind] = const CloudSyncResult(failed: 1, note: '同步失败，请稍后重试');
      }
    }
    return CloudSyncReport(results);
  }

  /// 上传弹幕规则，并把启用的关键词补到直播间屏蔽词
  static Future<CloudSyncResult> pushDanmaku() async {
    final cloud = await _fetchDanmakuCloud();
    final cloudRules = <DanmakuCloudRule>[
      for (final rule in cloud.rule)
        DanmakuCloudRule(type: 0, filter: rule.filter),
      for (final rule in cloud.rule1)
        DanmakuCloudRule(type: 1, filter: rule.filter),
      for (final rule in cloud.rule2)
        DanmakuCloudRule(type: 2, filter: rule.filter),
    ];
    final local = RuleStore.instance.rules;
    final diff = diffDanmakuPush(cloud: cloudRules, local: local);

    var added = 0;
    var failed = 0;
    for (final rule in diff) {
      final result = await DanmakuFilterHttp.danmakuFilterAdd(
        filter: rule.filter,
        type: rule.type,
      );
      if (result.isSuccess) {
        added++;
      } else {
        failed++;
      }
    }

    // 直播间屏蔽词没有读取接口，只能逐个补，重复添加按成功处理
    var liveAdded = 0;
    var liveFailed = 0;
    final keywords = <String>{};
    for (final rule in local) {
      if (!rule.enabled ||
          rule.type != RuleType.keyword ||
          !rule.scopes.contains(RuleScope.danmaku)) {
        continue;
      }
      if (!keywords.add(rule.content)) continue;
      final result = await LiveHttp.addShieldKeyword(keyword: rule.content);
      if (result.isSuccess) {
        liveAdded++;
      } else if (result is Error && isAlreadyExistsMessage(result.errMsg)) {
        liveAdded++;
      } else {
        liveFailed++;
      }
    }

    return CloudSyncResult(
      success: added + liveAdded,
      failed: failed + liveFailed,
      note: liveAdded + liveFailed == 0
          ? null
          : '直播屏蔽词 成功 $liveAdded 条，失败 $liveFailed 条',
    );
  }

  /// 上传私信屏蔽词
  static Future<CloudSyncResult> pushWhisper() async {
    final state = await ImGrpc.keywordBlockingList();
    final reply = switch (state) {
      Success(:final response) => response,
      _ => null,
    };
    if (reply == null) {
      throw BackupException('读取私信屏蔽词失败：${_errorMessage(state)}');
    }

    final local = [
      for (final rule in RuleStore.instance.rules)
        if (rule.enabled &&
            rule.type == RuleType.keyword &&
            rule.scopes.contains(RuleScope.whisper))
          rule.content,
    ];
    final plan = planWhisperPush(
      local: local,
      cloud: [for (final item in reply.items) item.keyword],
      listLimit: reply.listLimit,
      charLimit: reply.charLimit,
    );

    var added = 0;
    var failed = 0;
    for (final keyword in plan.toAdd) {
      final result = await ImGrpc.keywordBlockingAdd(keyword);
      if (result.isSuccess) {
        added++;
      } else if (result is Error && isAlreadyExistsMessage(result.errMsg)) {
        added++;
      } else {
        failed++;
      }
    }

    final notes = <String>[
      if (plan.tooLong > 0) '${plan.tooLong} 条超过字符上限',
      if (plan.overLimit > 0) '${plan.overLimit} 条超过列表上限',
    ];
    return CloudSyncResult(
      success: added,
      skipped: plan.skipped,
      failed: failed,
      note: notes.isEmpty ? null : notes.join('，'),
    );
  }

  /// 上传黑名单：分页读完云端后逐个拉黑，限流时立即停止
  static Future<CloudSyncResult> pushBlacklist() async {
    final cloud = await _fetchBlacklistMids();
    final missing = missingBlacklistMids(
      local: GlobalData().blackMids,
      cloud: cloud,
    ).toList()..sort();

    var added = 0;
    var skipped = 0;
    var failed = 0;
    String? stopped;
    for (var i = 0; i < missing.length; i++) {
      if (i > 0) await Future<void>.delayed(_blacklistInterval);
      final result = await VideoHttp.relationMod(
        mid: missing[i],
        act: 5,
        reSrc: 11,
      );
      if (result.isSuccess) {
        added++;
        continue;
      }
      final message = result is Error ? result.errMsg : null;
      if (isRateLimitedMessage(message)) {
        failed++;
        skipped = missing.length - i - 1;
        stopped = '遇到限流或风控，已停止：${message ?? '请稍后重试'}';
        break;
      }
      failed++;
    }

    return CloudSyncResult(
      success: added,
      skipped: skipped,
      failed: failed,
      note: stopped,
    );
  }

  /// 下载云端弹幕规则并合并到本地
  static Future<CloudSyncResult> pullDanmaku() async {
    final cloud = await _fetchDanmakuCloud();
    final plan = planDanmakuPull(
      cloud: [
        for (final rule in cloud.rule)
          DanmakuCloudRule(type: 0, filter: rule.filter),
        for (final rule in cloud.rule1)
          DanmakuCloudRule(type: 1, filter: rule.filter),
        for (final rule in cloud.rule2)
          DanmakuCloudRule(type: 2, filter: rule.filter),
      ],
      local: RuleStore.instance.rules,
    );
    if (plan.rules.isNotEmpty) {
      RuleStore.instance.addAll(plan.rules);
    }
    return CloudSyncResult(success: plan.rules.length, skipped: plan.skipped);
  }

  /// 下载私信屏蔽词并合并到本地
  static Future<CloudSyncResult> pullWhisper() async {
    final state = await ImGrpc.keywordBlockingList();
    final reply = switch (state) {
      Success(:final response) => response,
      _ => null,
    };
    if (reply == null) {
      throw BackupException('读取私信屏蔽词失败：${_errorMessage(state)}');
    }

    final plan = planWhisperPull(
      cloud: [for (final item in reply.items) item.keyword],
      local: RuleStore.instance.rules,
    );
    if (plan.rules.isNotEmpty) {
      RuleStore.instance.addAll(plan.rules);
    }
    return CloudSyncResult(success: plan.rules.length, skipped: plan.skipped);
  }

  /// 下载在线黑名单并合并到本地
  static Future<CloudSyncResult> pullBlacklist() async {
    final cloud = await _fetchBlacklistMids();
    final plan = planBlacklistPull(
      cloud: cloud,
      local: GlobalData().blackMids,
    );
    if (plan.isNotEmpty) {
      RuleStore.instance.addAll(plan);
    }
    return CloudSyncResult(
      success: plan.length,
      skipped: cloud.length - plan.length,
    );
  }

  static Future<DanmakuBlockDataModel> _fetchDanmakuCloud() async {
    final state = await DanmakuFilterHttp.danmakuFilter();
    if (state is Success<DanmakuBlockDataModel>) return state.response;
    throw BackupException('读取云端弹幕规则失败：${_errorMessage(state)}');
  }

  static Future<Set<int>> _fetchBlacklistMids() async {
    const pageSize = 50;
    final mids = <int>{};
    var page = 1;
    var fetched = 0;
    while (true) {
      final state = await BlackHttp.blackList(pn: page, ps: pageSize);
      if (state is! Success<BlackListData>) {
        throw BackupException('读取 B 站在线黑名单失败：${_errorMessage(state)}');
      }
      final data = state.response;
      final list = data.list;
      if (list == null || list.isEmpty) break;
      for (final item in list) {
        final mid = item.mid;
        if (mid != null && mid > 0) mids.add(mid);
      }
      fetched += list.length;
      final total = data.total;
      if (list.length < pageSize) break;
      if (total != null && fetched >= total) break;
      page++;
      // 兜底，避免接口异常时一直翻页
      if (page > 500) break;
    }
    return mids;
  }

  static String _errorMessage(LoadingState state) {
    if (state is Error) {
      final message = state.errMsg;
      if (message != null && message.isNotEmpty) return message;
    }
    return '请求失败';
  }
}
