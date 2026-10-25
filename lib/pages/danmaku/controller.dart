import 'dart:collection';
import 'dart:io' show File;

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/pages/danmaku/judge_context.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_engine.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path/path.dart' as path;

class PlDanmakuController {
  PlDanmakuController(
    this._cid,
    this._plPlayerController,
    this._isFileSource, [
    this._judgeContext,
  ]) : _mergeDanmaku = _plPlayerController.mergeDanmaku;

  final int _cid;
  final PlPlayerController _plPlayerController;
  final bool _mergeDanmaku;
  final bool _isFileSource;
  final DanmakuJudgeContext? _judgeContext;

  late final _isLogin = Accounts.main.isLogin;

  final Map<int, List<DanmakuElem>> _dmSegMap = HashMap();
  // 已请求的段落标记
  late final Set<int> _requestedSeg = HashSet();

  /// AI 判定进行中
  final ValueNotifier<bool> judging = ValueNotifier(false);

  // 每块交给 AI 判定的弹幕数
  static const int _judgeChunkSize = 80;

  bool _disposed = false;
  int _pendingChunks = 0;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dmSegMap.clear();
    _requestedSeg.clear();
    judging.dispose();
  }

  Future<void> queryDanmaku(int segmentIndex) async {
    if (_disposed || _isFileSource) {
      return;
    }
    if (_requestedSeg.contains(segmentIndex)) {
      return;
    }
    _requestedSeg.add(segmentIndex);
    final res = await DmGrpc.dmSegMobile(
      cid: _cid,
      segmentIndex: segmentIndex + 1,
    );

    if (_disposed) {
      return;
    }
    if (res case Success(:final response)) {
      if (response.state == 1) {
        _plPlayerController.dmState.add(_cid);
      }
      handleDanmaku(response.elems);
    } else {
      _requestedSeg.remove(segmentIndex);
    }
  }

  void handleDanmaku(List<DanmakuElem> elems) {
    if (_disposed || elems.isEmpty) return;
    final snap = RuleEngine.instance.snapshot(RuleScope.danmaku);
    final uniques = HashMap<String, DanmakuElem>();
    final passed = <DanmakuElem>[];
    final candidates = <DanmakuElem>[];

    for (final element in elems) {
      if (_isLogin) {
        element.isSelf = element.midHash == _plPlayerController.midHash;
      }

      if (!element.isSelf) {
        if (_mergeDanmaku) {
          final elem = uniques[element.content];
          if (elem == null) {
            uniques[element.content] = element..count = 1;
          } else {
            elem.count++;
            continue;
          }
        }

        if (snap.matchText(element.content) ||
            snap.hashBlocked(element.midHash, text: element.content)) {
          continue;
        }
      }

      passed.add(element);
      if (!element.isSelf) {
        candidates.add(element);
      }
    }

    // 本地弹幕文件不走网络判定，保持原有加载行为
    if (_isFileSource ||
        candidates.isEmpty ||
        !AiFilterRuntime.instance.isActiveFor(FilterSurface.danmaku)) {
      for (final element in passed) {
        _addToMap(element);
      }
      return;
    }

    // 自己发的弹幕不判定，直接放出
    for (final element in passed) {
      if (element.isSelf) {
        _addToMap(element);
      }
    }

    candidates.sort((a, b) => a.progress.compareTo(b.progress));
    final title = _judgeBackground();
    final chunks = _chunkDanmaku(candidates);
    _pendingChunks += chunks.length;
    judging.value = true;
    for (final chunk in chunks) {
      _judgeChunk(chunk, title);
    }
  }

  /// 按时间顺序把弹幕切成每块 [_judgeChunkSize] 条
  List<List<DanmakuElem>> _chunkDanmaku(List<DanmakuElem> items) {
    final chunks = <List<DanmakuElem>>[];
    for (var start = 0; start < items.length; start += _judgeChunkSize) {
      final int end = start + _judgeChunkSize;
      chunks.add(
        items.sublist(start, end > items.length ? items.length : end),
      );
    }
    return chunks;
  }

  /// 判定一块弹幕；失败整块放行，完成后立即写入待展示数据
  Future<void> _judgeChunk(List<DanmakuElem> chunk, String title) async {
    var passed = chunk;
    try {
      final ids = _judgeIds(chunk);
      final result = await AiFilterRuntime.instance.judge(
        surface: FilterSurface.danmaku,
        items: <JudgeItem>[
          for (var i = 0; i < chunk.length; i++)
            JudgeItem(id: ids[i], text: chunk[i].content),
        ],
        title: title,
      );
      if (result != null) {
        final visible = <DanmakuElem>[];
        for (var i = 0; i < chunk.length; i++) {
          final verdict = result.verdicts[ids[i]];
          if (verdict == null || !verdict.blocked) {
            visible.add(chunk[i]);
          }
        }
        passed = visible;
      }
    } catch (_) {
      // 判定失败整块放行
      passed = chunk;
    }

    if (_disposed) return;
    try {
      for (final element in passed) {
        _addToMap(element);
      }
    } finally {
      _pendingChunks--;
      if (_pendingChunks <= 0) {
        _pendingChunks = 0;
        judging.value = false;
      }
    }
  }

  /// 段内弹幕 id 可能重复，重复时改用下标避免判定结果互相覆盖
  List<String> _judgeIds(List<DanmakuElem> chunk) {
    final ids = <String>[];
    final seen = <String>{};
    for (final element in chunk) {
      final id = element.id.toString();
      if (!seen.add(id)) {
        return <String>[for (var i = 0; i < chunk.length; i++) '$i'];
      }
      ids.add(id);
    }
    return ids;
  }

  String _judgeBackground() {
    final context = _judgeContext;
    if (context == null) {
      return '';
    }
    try {
      final title = context.title();
      final partition = context.partition().trim();
      return partition.isEmpty ? title : '$title（分区：$partition）';
    } catch (_) {
      return '';
    }
  }

  void _addToMap(DanmakuElem element) {
    final int pos = element.progress ~/ 100; //每0.1秒存储一次
    (_dmSegMap[pos] ??= []).add(element);
  }

  List<DanmakuElem>? getCurrentDanmaku(int progress) {
    if (_disposed) return null;
    if (_isFileSource) {
      initFileDmIfNeeded();
    } else {
      final int segmentIndex = DmUtils.calcSegment(progress);
      if (!_requestedSeg.contains(segmentIndex)) {
        queryDanmaku(segmentIndex);
        return null;
      }
      // 过半后预取下一段
      if (progress - segmentIndex * DmUtils.segLength >=
          DmUtils.segLength ~/ 2) {
        final int nextSegment = segmentIndex + 1;
        if (!_requestedSeg.contains(nextSegment)) {
          queryDanmaku(nextSegment);
        }
      }
    }
    return _dmSegMap[progress ~/ 100];
  }

  bool _fileDmLoaded = false;

  void initFileDmIfNeeded() {
    if (_fileDmLoaded) return;
    _fileDmLoaded = true;
    _initFileDm();
  }

  @pragma('vm:notify-debugger-on-exception')
  Future<void> _initFileDm() async {
    try {
      final file = File(
        path.join(
          (_plPlayerController.dataSource as FileSource).dir,
          PathUtils.danmakuName,
        ),
      );
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      final elem = DmSegMobileReply.fromBuffer(bytes).elems;
      handleDanmaku(elem);
    } catch (e, s) {
      Utils.reportError(e, s);
    }
  }
}
