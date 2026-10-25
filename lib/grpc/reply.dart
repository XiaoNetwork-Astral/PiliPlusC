import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart';
import 'package:PiliPlus/grpc/grpc_req.dart';
import 'package:PiliPlus/grpc/url.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_rule.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_scope.dart';
import 'package:PiliPlus/models/cognitive_filter/rule_type.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_engine.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:fixnum/fixnum.dart';

abstract final class ReplyGrpc {
  static bool antiGoodsReply = Pref.antiGoodsReply;
  static var blockAtOnlyReply = Pref.blockAtOnlyReply;
  static var blockReplyAtCount = Pref.blockReplyAtCount;
  // 仅兼容旧版设置页的写入，评论过滤已统一读规则引擎
  static RegExp replyRegExp = RegExp('');
  static bool enableFilter = false;

  // static Future replyInfo({required int rpid}) {
  //   return _request(
  //     GrpcUrl.replyInfo,
  //     ReplyInfoReq(rpid: Int64(rpid)),
  //     ReplyInfoReply.fromBuffer,
  //     onSuccess: (response) => response.reply,
  //   );
  // }

  static bool _hasGoods(Url url) =>
      url.hasExtra() &&
      (url.extra.goodsCmControl == Int64.ONE ||
          url.extra.hasGoodsItemId() ||
          url.extra.hasGoodsPrefetchedCache());

  // ref BiliRoamingX
  @pragma('vm:prefer-inline')
  static bool _needRemoveGoodGrpc(ReplyInfo reply) {
    return (reply.content.urls.isNotEmpty &&
            reply.content.urls.values.any(_hasGoods)) ||
        reply.content.message.contains(Constants.goodsUrlPrefix);
  }

  static bool _blockAtOnlyReply(ReplyInfo reply) {
    if (!blockAtOnlyReply) return false;

    final content = reply.content;
    final atNameToMid = content.atNameToMid;
    if (atNameToMid.isEmpty) return false;
    if (content.emotes.isNotEmpty || content.pictures.isNotEmpty) return false;

    final message = content.message;
    final length = message.length;

    int i = 0;

    if (reply.root != reply.parent) {
      i = message.indexOf(':') + 1;
      if (i <= 0) return false;
    }

    var hasAt = false;
    while (i < length) {
      var c = message.codeUnitAt(i);

      if (c case 0x20 /* ` ` */ || 0x0A /* `\n` */ ) {
        i++;
        continue;
      }

      if (c != 0x40 /* `@` */ ) return false;

      i++;
      final nameStart = i;

      while (i < length) {
        c = message.codeUnitAt(i);
        if (c case 0x20 || 0x40 || 0x0A) {
          break;
        }
        i++;
      }

      if (i == nameStart) return false;
      final name = message.substring(nameStart, i);
      if (!atNameToMid.containsKey(name)) return false;

      hasAt = true;
    }

    return hasAt;
  }

  static bool _blockReplyAtCount(ReplyInfo reply) {
    return blockReplyAtCount != null &&
        reply.content.atNameToMid.length >= blockReplyAtCount!;
  }

  /// 判断单条评论是否剔除；快照与总开关由调用方按页只取一次
  static bool needRemoveGrpc(
    ReplyInfo reply,
    RuleSnapshot snap,
    bool enabled,
  ) {
    if (!enabled) return false;
    return snap.userBlocked(reply.mid.toInt()) ||
        _blockReplyAtCount(reply) ||
        _blockAtOnlyReply(reply) ||
        (antiGoodsReply && _needRemoveGoodGrpc(reply)) ||
        snap.matchText(reply.content.message);
  }

  /// 把选中文本添加为 reply 范围的关键词规则
  static bool addKeywordReplyRule(String text) {
    if (text.trim().isEmpty) return false;
    RuleStore.instance.add(
      FilterRule(
        id: FilterRule.nextId(),
        type: RuleType.keyword,
        content: text,
        scopes: const {RuleScope.reply},
      ),
    );
    return true;
  }

  static Future<LoadingState<MainListReply>> mainList({
    int type = 1,
    required int oid,
    Int64? rpid,
    required Mode mode,
    required String? offset,
    required Int64? cursorNext,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.mainList,
      MainListReq(
        oid: Int64(oid),
        type: Int64(type),
        rpid: rpid,
        cursor: CursorReq(
          mode: mode,
          next: cursorNext,
        ),
        // mode: mode,
        // pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      MainListReply.fromBuffer,
    );
    if (res case Success(:final response)) {
      final snap = RuleEngine.instance.snapshot(RuleScope.reply);
      final enabled = Pref.cfRuleFilterEnabled;
      if (response.hasUpTop() &&
          needRemoveGrpc(response.upTop, snap, enabled)) {
        response.clearUpTop();
      }

      if (response.replies.isNotEmpty) {
        response.replies.removeWhere((item) {
          final hasMatch = needRemoveGrpc(item, snap, enabled);
          if (!hasMatch && item.replies.isNotEmpty) {
            item.replies.removeWhere(
              (e) => needRemoveGrpc(e, snap, enabled),
            );
          }
          return hasMatch;
        });
      }
    }
    return res;
  }

  static Future<LoadingState<DetailListReply>> detailList({
    int type = 1,
    required int oid,
    required int root,
    required int rpid,
    required Mode mode,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.detailList,
      DetailListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        rpid: Int64(rpid),
        scene: DetailListScene.REPLY,
        mode: mode,
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DetailListReply.fromBuffer,
    );
    if (res.dataOrNull?.root.replies case final replies?) {
      final snap = RuleEngine.instance.snapshot(RuleScope.reply);
      final enabled = Pref.cfRuleFilterEnabled;
      replies.removeWhere((e) => needRemoveGrpc(e, snap, enabled));
    }
    return res;
  }

  static Future<LoadingState<DialogListReply>> dialogList({
    int type = 1,
    required int oid,
    required int root,
    required int dialog,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.dialogList,
      DialogListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        dialog: Int64(dialog),
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DialogListReply.fromBuffer,
    );
    if (res.dataOrNull?.replies case final replies?) {
      final snap = RuleEngine.instance.snapshot(RuleScope.reply);
      final enabled = Pref.cfRuleFilterEnabled;
      replies.removeWhere((e) => needRemoveGrpc(e, snap, enabled));
    }
    return res;
  }

  static Future<LoadingState<SearchItemReply>> searchItem({
    required int page,
    required SearchItemType itemType,
    required int oid,
    int type = 1,
    String? keyword,
  }) {
    return GrpcReq.request(
      GrpcUrl.searchItem,
      SearchItemReq(
        cursor: SearchItemCursorReq(
          next: Int64(page),
          itemType: itemType,
        ),
        oid: Int64(oid),
        type: Int64(type),
        keyword: keyword,
      ),
      SearchItemReply.fromBuffer,
    );
  }

  static Future<LoadingState<TranslateReplyResp>> translateReply({
    required Int64 type,
    required Int64 oid,
    required Int64 rpid,
  }) {
    return GrpcReq.request(
      GrpcUrl.translateReply,
      TranslateReplyReq(
        type: type,
        oid: oid,
        rpids: [rpid],
      ),
      TranslateReplyResp.fromBuffer,
    );
  }
}
