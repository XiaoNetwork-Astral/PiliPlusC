import 'package:PiliPlus/utils/parse_int.dart';

class LiveFollowItem {
  int? roomid;
  int? uid;
  String? uname;
  String? title;
  String? areaName;
  String? textSmall;
  String? roomCover;

  LiveFollowItem({
    this.roomid,
    this.uid,
    this.uname,
    this.title,
    this.areaName,
    this.textSmall,
    this.roomCover,
  });

  factory LiveFollowItem.fromJson(Map<String, dynamic> json) => LiveFollowItem(
    roomid: json['roomid'] as int?,
    uid: safeToInt(json['uid']),
    uname: json['uname'] as String?,
    title: json['title'] as String?,
    areaName: json['area_name'] as String?,
    textSmall: json['text_small'] as String?,
    roomCover: json['room_cover'] as String?,
  );
}
