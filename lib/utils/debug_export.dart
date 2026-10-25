import 'dart:convert' show JsonEncoder, utf8;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 调试用：导出当前视频的全部弹幕和字幕
abstract final class DebugExport {
  static Future<void> exportDanmakuAndSubtitles({
    required String bvid,
    required int aid,
    required int cid,
    required String title,
    required int? durationMs,
    required List<Subtitle> subtitles,
  }) async {
    SmartDialog.showLoading();
    try {
      final errors = <String>[];
      final totalSegments = _segmentCount(durationMs);
      final danmaku = <({DanmakuElem elem, int segment})>[];
      final danmakuSegments = <Map<String, dynamic>>[];

      for (var segment = 1; segment <= totalSegments; segment++) {
        try {
          final res = await DmGrpc.dmSegMobile(
            cid: cid,
            segmentIndex: segment,
          );
          if (res case Success(:final response)) {
            final elems = response.elems;
            danmaku.addAll(
              elems.map((elem) => (elem: elem, segment: segment)),
            );
            danmakuSegments.add({
              'segment': segment,
              'ok': true,
              'count': elems.length,
            });
          } else {
            errors.add('弹幕分段 $segment 获取失败：${_errorText(res)}');
            danmakuSegments.add({
              'segment': segment,
              'ok': false,
              'count': 0,
            });
          }
        } catch (e) {
          errors.add('弹幕分段 $segment 获取失败：${_errorText(e)}');
          danmakuSegments.add({
            'segment': segment,
            'ok': false,
            'count': 0,
          });
        }
      }

      danmaku.sort((a, b) {
        final progress = a.elem.progress.compareTo(b.elem.progress);
        if (progress != 0) return progress;
        return a.elem.id.compareTo(b.elem.id);
      });

      final subtitleList = <Map<String, dynamic>>[];
      for (final subtitle in subtitles) {
        final lanDoc = subtitle.lanDoc;
        final label = lanDoc == null || lanDoc.isEmpty
            ? subtitle.lan
            : lanDoc;
        final url = _subtitleUrl(subtitle);
        if (url == null) {
          if (subtitle.lan.isNotEmpty) {
            errors.add('字幕 $label 获取失败：缺少字幕地址');
          }
          continue;
        }
        try {
          final items = await VideoHttp.getSubtitleItems(url);
          if (items == null) {
            errors.add('字幕 $label 获取失败：未获取到字幕内容');
            continue;
          }
          final parsed = items
              .map(
                (item) => (
                  fromMs: _toMs(item['from']),
                  toMs: _toMs(item['to']),
                  content: item['content']?.toString() ?? '',
                ),
              )
              .toList()
            ..sort((a, b) => a.fromMs.compareTo(b.fromMs));
          subtitleList.add({
            'lan': subtitle.lan,
            'lanDoc': subtitle.lanDoc ?? '',
            'isAi': subtitle.isAi,
            'items': parsed
                .map(
                  (item) => {
                    'fromMs': item.fromMs,
                    'toMs': item.toMs,
                    'content': item.content,
                  },
                )
                .toList(),
          });
        } catch (e) {
          errors.add('字幕 $label 获取失败：${_errorText(e)}');
        }
      }

      final data = <String, dynamic>{
        'exportVersion': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'video': {
          'bvid': bvid,
          'aid': aid,
          'cid': cid,
          'title': title,
          'durationMs': durationMs ?? 0,
          'isLogin': Accounts.main.isLogin,
        },
        'subtitles': subtitleList,
        'danmaku': [
          for (final entry in danmaku)
            _danmakuToJson(entry.elem, entry.segment),
        ],
        'danmakuSegments': danmakuSegments,
        'errors': errors,
      };

      final text = const JsonEncoder.withIndent('  ').convert(data);
      SmartDialog.dismiss();
      final saved = await _saveFile(
        fileName: 'piliplusc_dm_sub_${bvid}_$cid.json',
        bytes: utf8.encode(text),
      );
      if (!saved) return;
      SmartDialog.showToast(
        errors.isEmpty ? '导出成功' : '导出成功，部分内容未获取',
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('导出失败：${_errorText(e)}');
    }
  }

  static int _segmentCount(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return 1;
    final count = (durationMs + DmUtils.segLength - 1) ~/ DmUtils.segLength;
    return count < 1 ? 1 : count;
  }

  static int _toMs(Object? seconds) {
    if (seconds is num) {
      return (seconds * 1000).round();
    }
    return 0;
  }

  static String? _subtitleUrl(Subtitle subtitle) {
    final url = subtitle.subtitleUrl;
    if (url != null && url.isNotEmpty) return url;
    final urlV2 = subtitle.subtitleUrlV2;
    if (urlV2 != null && urlV2.isNotEmpty) return urlV2;
    return null;
  }

  static String _errorText(Object error) {
    final text = error.toString().replaceAll(
      RegExp(r'https?://[^\s]+'),
      '<链接已隐藏>',
    );
    return text.isEmpty ? '未知错误' : text;
  }

  static Map<String, dynamic> _danmakuToJson(
    DanmakuElem elem,
    int segment,
  ) {
    final json = <String, dynamic>{
      'id': elem.id.toString(),
      'progressMs': elem.progress,
      'content': elem.content,
      'mode': elem.mode,
      'fontsize': elem.fontsize,
      'color': elem.color,
      'ctime': elem.ctime.toInt() * 1000, // protobuf 为秒，统一转毫秒
      'weight': elem.weight,
      'midHash': elem.midHash,
      'segment': segment,
    };
    if (elem.hasLikeCount()) {
      json['likeCount'] = elem.likeCount.toInt();
    }
    return json;
  }

  static Future<bool> _saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final savePath = await FilePicker.saveFile(
      fileName: fileName,
      bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
      mimeType: 'application/json',
    );
    if (savePath == null) {
      SmartDialog.showToast('已取消导出');
      return false;
    }
    if (PlatformUtils.isDesktop) {
      await File(savePath.toFilePath()).writeAsBytes(bytes);
    }
    return true;
  }
}
