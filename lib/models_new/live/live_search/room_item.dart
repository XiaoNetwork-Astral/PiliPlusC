import 'package:PiliPlus/models_new/live/live_feed_index/watched_show.dart';
import 'package:PiliPlus/utils/parse_int.dart';

class LiveSearchRoomItemModel {
  int? roomid;
  int? uid;
  String? cover;
  String? title;
  String? name;
  String? areaName;
  String? face;
  WatchedShow? watchedShow;

  LiveSearchRoomItemModel({
    this.roomid,
    this.uid,
    this.cover,
    this.title,
    this.name,
    this.areaName,
    this.face,
    this.watchedShow,
  });

  factory LiveSearchRoomItemModel.fromJson(Map<String, dynamic> json) =>
      LiveSearchRoomItemModel(
        roomid: json['roomid'] as int?,
        uid: safeToInt(json['uid']),
        cover: json['cover'] as String?,
        title: json['title'] as String?,
        name: json['name'] as String?,
        areaName:
            json['area_name'] as String? ?? json['areaName'] as String?,
        face: json['face'] as String?,
        watchedShow: json['watched_show'] == null
            ? null
            : WatchedShow.fromJson(
                json['watched_show'] as Map<String, dynamic>,
              ),
      );
}
