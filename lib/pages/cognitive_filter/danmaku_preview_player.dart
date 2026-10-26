import 'dart:async';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 屏蔽详情里直接播放被屏蔽弹幕所在的那段视频
///
/// 取不到播放地址、打开失败或播放出错时只保留纯黑底与 [child]
class DanmakuPreviewPlayer extends StatefulWidget {
  const DanmakuPreviewPlayer({
    super.key,
    required this.meta,
    required this.child,
    this.onVideoReady,
  });

  /// 弹幕历史条目的 meta，需要 bvid 与 cid
  final Map<String, dynamic> meta;

  /// 叠在视频画面上的弹幕动画层
  final Widget child;

  /// 视频开始出画（或确认只能显示黑底）时回调，用于同步启动弹幕动画
  final VoidCallback? onVideoReady;

  @override
  State<DanmakuPreviewPlayer> createState() => DanmakuPreviewPlayerState();
}

class DanmakuPreviewPlayerState extends State<DanmakuPreviewPlayer> {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _errorSubscription;
  Timer? _readyTimer;
  bool _notified = false;
  bool _disposed = false;
  bool _failed = false;
  bool _playerReleased = false;
  int _startMs = 0;

  @override
  void initState() {
    super.initState();
    _startMs = _asInt(widget.meta['progressMs']) ?? 0;
    unawaited(_init());
  }

  @override
  void dispose() {
    _disposed = true;
    _readyTimer?.cancel();
    _playingSubscription?.cancel();
    _errorSubscription?.cancel();
    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) {
      _releasePlayer(player);
    }
    super.dispose();
  }

  /// 每个 State 只会创建一个 Player，重复释放会抛异常
  void _releasePlayer(Player player) {
    if (_playerReleased) {
      return;
    }
    _playerReleased = true;
    unawaited(player.dispose());
  }

  /// 点击画布重播：回到弹幕出现的时间点，再通知上层重播动画
  void replay() {
    if (_disposed) {
      return;
    }
    _notified = false;
    final player = _player;
    if (player == null) {
      // 已确认拿不到视频就只重播动画；还在初始化就等它自己回调
      if (_failed) {
        _notifyReady();
      }
      return;
    }
    unawaited(_replay(player));
  }

  Future<void> _replay(Player player) async {
    try {
      await player
          .seek(Duration(milliseconds: _startMs))
          .timeout(const Duration(seconds: 8));
      await player.play().timeout(const Duration(seconds: 8));
    } catch (_) {
      // 重播失败也不影响弹幕动画
    }
    _notifyReady();
  }

  Future<void> _init() async {
    final bvid = _asString(widget.meta['bvid']);
    final cid = _asInt(widget.meta['cid']);
    if (bvid == null || cid == null) {
      // 缺定位信息，只能显示黑底
      _failed = true;
      _notifyReady();
      return;
    }
    try {
      final url = await _resolveUrl(bvid: bvid, cid: cid);
      if (_disposed) {
        return;
      }
      if (url == null) {
        _failed = true;
        _notifyReady();
        return;
      }
      await _open(url);
    } catch (_) {
      _fail();
    }
  }

  Future<String?> _resolveUrl({required String bvid, required int cid}) async {
    final name = widget.meta['videoType'];
    final videoType =
        (name is String ? VideoType.values.asNameMap()[name] : null) ??
        VideoType.ugc;
    final result = await VideoHttp.videoUrl(
      avid: _asInt(widget.meta['aid']),
      bvid: bvid,
      cid: cid,
      // 最低清晰度，预览够用又省流量
      qn: 16,
      epid: _asInt(widget.meta['epId']),
      seasonId: _asInt(widget.meta['seasonId']),
      tryLook: true,
      videoType: videoType,
    ).timeout(const Duration(seconds: 8));
    if (result case Success(:final response)) {
      return _pickUrl(response);
    }
    return null;
  }

  /// 优先分辨率最小且编码为 avc 的画面，只取画面不取音频
  String? _pickUrl(PlayUrlModel playUrl) {
    final videos = playUrl.dash?.video;
    if (videos != null && videos.isNotEmpty) {
      final sorted = [...videos]
        ..sort((a, b) {
          final byPixels = _pixels(a).compareTo(_pixels(b));
          if (byPixels != 0) {
            return byPixels;
          }
          return (a.bandWidth ?? 0).compareTo(b.bandWidth ?? 0);
        });
      final avc = sorted.where(
        (item) => (item.codecs ?? '').toLowerCase().startsWith('avc'),
      );
      final pick = avc.isNotEmpty ? avc.first : sorted.first;
      final urls = pick.playUrls;
      if (urls.isNotEmpty) {
        return urls.first;
      }
    }
    final durl = playUrl.durl;
    if (durl != null && durl.isNotEmpty) {
      return durl.first.url;
    }
    return null;
  }

  int _pixels(VideoItem item) => (item.width ?? 0) * (item.height ?? 0);

  Future<void> _open(String url) async {
    Player? player;
    try {
      final created = await Player.create(
        configuration: const PlayerConfiguration(
          logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
        ),
      );
      player = created;
      if (!mounted || _disposed) {
        _releasePlayer(created);
        return;
      }
      final controller = await VideoController.create(
        created,
        configuration: const VideoControllerConfiguration(
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      if (!mounted || _disposed) {
        _releasePlayer(created);
        return;
      }
      created.setMediaHeader(
        userAgent: BrowserUa.pc,
        referer: HttpString.baseUrl,
      );
      _player = created;
      _videoController = controller;
      await created.setVolume(0);
      if (!mounted || _disposed) {
        return;
      }
      _playingSubscription = created.stream.playing.listen(_onPlaying);
      _errorSubscription = created.stream.error.listen(
        (_) => _onPlayerError(created),
      );
      setState(() {});
      // 长时间没有 playing 事件时也让弹幕先滚起来
      _readyTimer = Timer(const Duration(seconds: 10), _notifyReady);
      await created
          .open(Media(url, start: Duration(milliseconds: _startMs)), play: true)
          .timeout(const Duration(seconds: 10));
      if (!mounted || _disposed || !identical(_player, created)) {
        return;
      }
      if (created.state.playing) {
        _notifyReady();
      }
    } catch (_) {
      if (player != null && !identical(_player, player)) {
        _releasePlayer(player);
      }
      _fail();
    }
  }

  void _onPlaying(bool playing) {
    if (playing) {
      _notifyReady();
    }
  }

  void _onPlayerError(Player player) {
    if (_disposed || !identical(_player, player)) {
      return;
    }
    _fail();
  }

  void _fail() {
    if (_disposed) {
      return;
    }
    _failed = true;
    _readyTimer?.cancel();
    _readyTimer = null;
    _playingSubscription?.cancel();
    _playingSubscription = null;
    _errorSubscription?.cancel();
    _errorSubscription = null;
    final player = _player;
    final hadVideo = _videoController != null;
    _player = null;
    _videoController = null;
    if (hadVideo && mounted) {
      setState(() {});
    }
    if (player != null) {
      if (mounted && hadVideo) {
        // 等 Video 组件先脱离画面再释放播放器
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _releasePlayer(player);
        });
      } else {
        _releasePlayer(player);
      }
    }
    _notifyReady();
  }

  void _notifyReady() {
    if (_notified || _disposed) {
      return;
    }
    _notified = true;
    _readyTimer?.cancel();
    _readyTimer = null;
    scheduleMicrotask(() {
      if (!mounted || _disposed) {
        return;
      }
      widget.onVideoReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            IgnorePointer(
              child: Video(
                controller: controller,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

String? _asString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
