import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_engine.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class RecommendFilter {
  static int minDurationForRcmd = Pref.minDurationForRcmd;
  static int minPlayForRcmd = Pref.minPlayForRcmd;
  static int minLikeRatioForRecommend = Pref.minLikeRatioForRecommend;
  static bool exemptFilterForFollowed = Pref.exemptFilterForFollowed;
  static bool applyFilterToRelatedVideos = Pref.applyFilterToRelatedVideos;
  // 仅兼容旧版设置页的写入，标题/分区过滤已统一读规则引擎
  static RegExp rcmdRegExp = RegExp('');
  static bool enableFilter = false;

  // (web/app)rcmd
  static bool filterWithExempt(
    BaseVideoItemModel videoItem,
    RuleSnapshot snap, {
    required bool enabled,
  }) {
    if (!enabled) return false;
    //由于相关视频中没有已关注标签，只能视为非关注视频
    if (videoItem.isFollowed && exemptFilterForFollowed) {
      return false;
    }
    return filterAll(videoItem, snap, enabled: enabled);
  }

  /// hot/rank/[filterAll]
  static bool filterLikeRatio(
    int? like,
    int? view, {
    required bool enabled,
  }) {
    if (!enabled || view == null) return false;
    return (view > -1 && view < minPlayForRcmd) ||
        (like != null &&
            like > -1 &&
            like * 100 < minLikeRatioForRecommend * view);
  }

  /// hot/rank/[filterAll]
  static bool filterTitle(String title, RuleSnapshot snap) =>
      snap.matchText(title);

  /// [filterAll]
  static bool filterDuration(int duration, {required bool enabled}) =>
      enabled && duration > 0 && duration < minDurationForRcmd;

  /// related/[filterWithExempt]
  static bool filterAll(
    BaseVideoItemModel videoItem,
    RuleSnapshot snap, {
    required bool enabled,
  }) {
    if (!enabled) return false;
    return filterDuration(videoItem.duration, enabled: enabled) ||
        filterLikeRatio(
          videoItem.stat.like,
          videoItem.stat.view,
          enabled: enabled,
        ) ||
        filterTitle(videoItem.title, snap);
  }
}
