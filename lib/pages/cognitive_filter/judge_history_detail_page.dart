import 'dart:convert';

import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    hide TextStyle;
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/horizontal_video_model.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/judge_history.dart';
import 'package:PiliPlus/utils/cognitive_filter/rule_store.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

/// 把任意视频模型摊平成水平卡片需要的模型
class _HorizontalFromItem extends HorizontalVideoModel {
  _HorizontalFromItem(BaseVideoItemModel item) {
    aid = item.aid;
    bvid = item.bvid;
    cid = item.cid;
    cover = item.cover;
    title = item.title;
    duration = item.duration;
    owner = item.owner;
    stat = item.stat;
    pubdate = item.pubdate ?? 0;
    desc = item.desc;
    isFollowed = item.isFollowed;
  }
}

/// 一条屏蔽历史的详情
class JudgeHistoryDetailPage extends StatefulWidget {
  const JudgeHistoryDetailPage({super.key, required this.entry});

  final JudgeHistoryEntry entry;

  @override
  State<JudgeHistoryDetailPage> createState() => _JudgeHistoryDetailPageState();
}

class _JudgeHistoryDetailPageState extends State<JudgeHistoryDetailPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _danmakuAnimation;
  bool _danmakuDone = false;
  Widget? _snapshot;

  JudgeHistoryEntry get _entry => widget.entry;

  @override
  void initState() {
    super.initState();
    _danmakuAnimation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _danmakuDone = true);
      }
    });
    _buildSnapshot();
    if (_type == 'danmaku') {
      _danmakuAnimation.forward();
    }
  }

  @override
  void dispose() {
    _danmakuAnimation.dispose();
    super.dispose();
  }

  String? get _type => _str('type');

  String? _str(String key) {
    final value = _entry.meta?[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  int? _int(String key) {
    final value = _entry.meta?[key];
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  FilterSurface? _surfaceOf(String label) {
    for (final surface in FilterSurface.values) {
      if (surface.label == label) {
        return surface;
      }
    }
    return null;
  }

  void _buildSnapshot() {
    final snapshot = _entry.snapshot;
    if (snapshot == null) {
      return;
    }
    try {
      switch (_type) {
        case 'reply': {
          final encoded = snapshot['reply'];
          if (encoded is! String) {
            return;
          }
          final reply = ReplyInfo.fromBuffer(base64Decode(encoded));
          if (!reply.hasMember() || !reply.hasContent()) {
            return;
          }
          _snapshot = IgnorePointer(
            child: ReplyItemGrpc(
              replyItem: reply,
              replyLevel: 0,
              needDivider: false,
            ),
          );
        }
        case 'video': {
          final raw = snapshot['json'];
          if (raw is! Map) {
            return;
          }
          final item = _restoreVideo(
            Map<String, dynamic>.from(raw),
            snapshot['model'],
          );
          if (item == null) {
            return;
          }
          _snapshot = VideoCardH(
            videoItem: item is HorizontalVideoModel
                ? item
                : _HorizontalFromItem(item),
          );
        }
        case 'dynamic': {
          final raw = snapshot['json'];
          if (raw is! Map) {
            return;
          }
          final item = DynamicItemModel.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (!(item.visible ?? true) ||
              (item.modules.moduleAuthor == null &&
                  item.modules.moduleDynamic == null)) {
            return;
          }
          _snapshot = IgnorePointer(
            child: DynamicPanel(item: item, isDetail: true),
          );
        }
      }
    } catch (_) {
      // 快照坏了就退回简易版，不让页面崩
      _snapshot = null;
    }
  }

  BaseVideoItemModel? _restoreVideo(
    Map<String, dynamic> json,
    Object? model,
  ) {
    try {
      switch (model) {
        case 'HotVideoItemModel':
          return HotVideoItemModel.fromJson(json);
        case 'SearchVideoItemModel':
          return SearchVideoItemModel.fromJson(json);
        case 'RcmdVideoItemModel':
          return RcmdVideoItemModel.fromJson(json);
        case 'RcmdVideoItemAppModel':
          return RcmdVideoItemAppModel.fromJson(json);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void _replayDanmaku() {
    if (_type != 'danmaku') {
      return;
    }
    setState(() => _danmakuDone = false);
    _danmakuAnimation
      ..reset()
      ..forward();
  }

  Future<void> _openVideo() async {
    final bvid = _str('bvid');
    final aid = _int('aid');
    if (bvid == null && aid == null) {
      return;
    }
    final page = await SearchHttp.ab2cWithDimension(bvid: bvid, aid: aid);
    if (page == null) {
      return;
    }
    PageUtils.toVideoPage(
      bvid: bvid,
      aid: aid,
      cid: page.cid,
      cover: _str('cover'),
      title: _str('title'),
    );
  }

  void _openLive() {
    PageUtils.toLiveRoom(_int('roomId'));
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _formatTime(DateTime time) =>
      '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  Widget _textOnly() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SelectableText(_entry.text),
    );
  }

  Widget _author(ThemeData theme, String? uname) {
    if (uname == null) {
      return const SizedBox.shrink();
    }
    return Text(
      uname,
      style: theme.textTheme.labelMedium!.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }

  Widget _buildOriginal(ThemeData theme) {
    final type = _type;
    if (type == 'danmaku') {
      return _buildDanmaku(theme);
    }
    final snapshot = _snapshot;
    if (snapshot != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: snapshot,
      );
    }
    return switch (type) {
      'reply' => _buildReplyFallback(theme),
      'video' => _buildVideoFallback(theme),
      'dynamic' => _buildDynamicFallback(theme),
      'live' => _buildLiveFallback(theme),
      _ => _textOnly(),
    };
  }

  Widget _buildReplyFallback(ThemeData theme) {
    final uname = _str('uname');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _author(theme, uname),
          if (uname != null) const SizedBox(height: 6),
          SelectableText(_entry.text),
        ],
      ),
    );
  }

  Widget _buildVideoFallback(ThemeData theme) {
    final cover = _str('cover');
    final title = _str('title');
    final uname = _str('uname');
    final canOpen = _str('bvid') != null || _int('aid') != null;
    if (cover == null && title == null && uname == null && !canOpen) {
      return _textOnly();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          if (uname != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _author(theme, uname),
            ),
          if (canOpen)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openVideo,
                child: const Text('打开视频'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDynamicFallback(ThemeData theme) {
    final uname = _str('uname');
    final title = _str('title');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _author(theme, uname),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          const SizedBox(height: 6),
          SelectableText(_entry.text),
        ],
      ),
    );
  }

  Widget _buildLiveFallback(ThemeData theme) {
    final cover = _str('cover');
    final title = _str('title');
    final uname = _str('uname');
    final roomId = _int('roomId');
    if (cover == null && title == null && uname == null && roomId == null) {
      return _textOnly();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          if (uname != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _author(theme, uname),
            ),
          if (roomId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openLive,
                child: const Text('打开直播间'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDanmaku(ThemeData theme) {
    final videoTitle = _str('videoTitle');
    final rawColor = _int('color');
    final color = rawColor == null || rawColor == 0
        ? Colors.white
        : Color(0xFF000000 | (rawColor & 0xFFFFFF));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _replayDanmaku,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedBuilder(
                animation: _danmakuAnimation,
                builder: (context, child) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: _danmakuDone
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _danmakuDone
                          ? Center(
                              child: Text(
                                _entry.text,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: color, fontSize: 18),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final left =
                                    width - width * 2 * _danmakuAnimation.value;
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: left,
                                      top: 0,
                                      bottom: 0,
                                      child: Center(
                                        child: Text(
                                          _entry.text,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (videoTitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '来自 $videoTitle',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _scoreText(Map<String, double>? scores) {
    if (scores == null) {
      return null;
    }
    final list = scores.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (list.isEmpty) {
      return null;
    }
    return list
        .map((e) => '${e.key} ${(e.value * 100).round()}%')
        .join('\n');
  }

  List<Widget> _buildJudgeTiles() {
    final entry = _entry;
    final tiles = <Widget>[
      CfTile(title: '来源', subtitle: entry.isRule ? '规则屏蔽' : 'AI 屏蔽'),
      CfTile(
        title: '适用面',
        subtitle: entry.surface.isEmpty ? '未记录' : entry.surface,
      ),
    ];
    if (entry.isRule) {
      tiles.add(
        CfTile(
          title: '规则类型',
          subtitle: entry.ruleType.isEmpty ? '未记录' : entry.ruleType,
        ),
      );
      tiles.add(
        CfTile(
          title: '规则内容',
          subtitle: entry.label.isEmpty ? '未记录' : entry.label,
        ),
      );
    } else {
      tiles.add(
        CfTile(
          title: '判定类别',
          subtitle: entry.label.isEmpty ? '未记录' : entry.label,
        ),
      );
      tiles.add(
        CfTile(title: '得分', subtitle: entry.score.toStringAsFixed(2)),
      );
      final scoreText = _scoreText(entry.scores);
      if (scoreText != null) {
        tiles.add(CfTile(title: '各类别概率', subtitle: scoreText));
      }
    }
    tiles.add(CfTile(title: '时间', subtitle: _formatTime(entry.time)));
    return tiles;
  }

  List<Widget> _buildActions() {
    final entry = _entry;
    return [
      CfTile(
        title: '复制文字',
        onTap: () {
          Clipboard.setData(ClipboardData(text: entry.text));
        },
      ),
      if (!entry.isRule)
        CfTile(
          title: '加入白名单',
          onTap: () {
            AiWhitelist.instance.addKeywordFromText(
              entry.text,
              surface: _surfaceOf(entry.surface),
            );
          },
        ),
      if (entry.isRule && entry.ruleId != null)
        CfTile(
          title: '删除这条规则',
          onTap: () {
            RuleStore.instance.remove(entry.ruleId!);
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(title: const Text('屏蔽详情')),
      body: ViewSafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _buildOriginal(theme),
            const SizedBox(height: 12),
            const Divider(height: 1),
            ..._buildJudgeTiles(),
            ..._buildActions(),
          ],
        ),
      ),
    );
  }
}
