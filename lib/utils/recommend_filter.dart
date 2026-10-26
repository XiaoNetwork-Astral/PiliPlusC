import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_engine.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class RecommendFilter {
  static int minDurationForRcmd = Pref.minDurationForRcmd;
  static int minPlayForRcmd = Pref.minPlayForRcmd;
  static int minLikeRatioForRecommend = Pref.minLikeRatioForRecommend;
  static bool exemptFilterForFollowed = Pref.exemptFilterForFollowed;
  static bool applyFilterToRelatedVideos = Pref.applyFilterToRelatedVideos;

  // (web/app)rcmd
  static bool filterWithExempt(
    BaseVideoItemModel videoItem,
    RuleSnapshot snap, {
    required bool enabled,
    RuleBlockDetail Function()? detail,
  }) {
    //由于相关视频中没有已关注标签，只能视为非关注视频
    if (videoItem.isFollowed && exemptFilterForFollowed) {
      return false;
    }
    return filterAll(videoItem, snap, enabled: enabled, detail: detail);
  }

  /// hot/rank/[filterAll]
  static bool filterLikeRatio(int? like, int? view) {
    if (view == null) return false;
    return (view > -1 && view < minPlayForRcmd) ||
        (like != null &&
            like > -1 &&
            like * 100 < minLikeRatioForRecommend * view);
  }

  /// hot/rank/[filterAll]
  static bool filterTitle(
    String title,
    RuleSnapshot snap, {
    RuleBlockDetail Function()? detail,
  }) => snap.matchText(title, detail: detail);

  /// [filterAll]
  static bool filterDuration(int duration) =>
      duration > 0 && duration < minDurationForRcmd;

  /// related/[filterWithExempt]
  static bool filterAll(
    BaseVideoItemModel videoItem,
    RuleSnapshot snap, {
    required bool enabled,
    RuleBlockDetail Function()? detail,
  }) {
    if (!enabled) return false;
    return filterDuration(videoItem.duration) ||
        filterLikeRatio(videoItem.stat.like, videoItem.stat.view) ||
        filterTitle(videoItem.title, snap, detail: detail);
  }
}
