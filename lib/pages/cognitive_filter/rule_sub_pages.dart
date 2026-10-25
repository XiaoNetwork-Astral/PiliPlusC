import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/pick_settings.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/pages/setting/models/dyn_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/reply_settings.dart';
import 'package:PiliPlus/pages/whisper_block/view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const List<String> _replyTitles = [
  '评论关键词过滤',
  '屏蔽带货评论',
  '屏蔽评论@数量',
  '屏蔽只包含@的评论',
  '屏蔽复制简介评论',
];

const List<String> _dynTitles = [
  '动态关键词过滤',
  '屏蔽带货动态',
];

const List<String> _videoTitles = [
  '标题关键词过滤',
  '分区关键词过滤',
  '点赞率过滤',
  '视频时长过滤',
  '播放量过滤',
  '已关注UP豁免推荐过滤',
  '过滤器也应用于详情页相关视频',
];

List<SettingsModel> replyRuleSettings() =>
    pickSettings(replySettings, _replyTitles);

List<SettingsModel> dynRuleSettings() => pickSettings(dynSettings, _dynTitles);

List<SettingsModel> videoRuleSettings() =>
    pickSettings(recommendSettings, _videoTitles);

double _bottomPadding(BuildContext context) =>
    MediaQuery.viewPaddingOf(context).bottom + 100;

/// 评论屏蔽
class ReplyRuleSubPage extends StatelessWidget {
  const ReplyRuleSubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('评论屏蔽')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: _bottomPadding(context)),
          children: [
            for (final item in replyRuleSettings()) item.widget,
          ],
        ),
      ),
    );
  }
}

/// 动态屏蔽
class DynRuleSubPage extends StatelessWidget {
  const DynRuleSubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('动态屏蔽')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: _bottomPadding(context)),
          children: [
            for (final item in dynRuleSettings()) item.widget,
          ],
        ),
      ),
    );
  }
}

/// 视频屏蔽
class VideoRuleSubPage extends StatelessWidget {
  const VideoRuleSubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('视频屏蔽')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: _bottomPadding(context)),
          children: [
            for (final item in videoRuleSettings()) item.widget,
          ],
        ),
      ),
    );
  }
}

/// 私信与直播
class MessageRuleSubPage extends StatelessWidget {
  const MessageRuleSubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('私信与直播')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: _bottomPadding(context)),
          children: [
            CfTile(
              icon: Icons.message_outlined,
              title: '消息屏蔽词',
              subtitle: '管理私信里的关键词屏蔽',
              onTap: () => Get.to(() => const WhisperBlockPage()),
            ),
          ],
        ),
      ),
    );
  }
}
