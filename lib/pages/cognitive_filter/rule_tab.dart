import 'package:PiliPlus/pages/cognitive_filter/danmaku_rule_pages.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_sub_pages.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 规则屏蔽页
///
/// 聚合原有的非 AI 过滤，本身不重复实现规则
class RuleFilterTab extends StatefulWidget {
  const RuleFilterTab({super.key});

  @override
  State<RuleFilterTab> createState() => _RuleFilterTabState();
}

class _RuleFilterTabState extends State<RuleFilterTab> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = Pref.cfRuleFilterEnabled;
  }

  void _toggle(bool value) {
    Pref.cfRuleFilterEnabled = value;
    setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return ListView(
      primary: true,
      key: const PageStorageKey<String>('cfRuleList'),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [
        CfSwitchTile(
          icon: Icons.filter_alt_outlined,
          title: '启用规则屏蔽',
          subtitle: '关闭后不再使用下列任何非 AI 过滤',
          value: _enabled,
          onChanged: _toggle,
        ),
        CfTile(
          icon: Icons.subtitles_outlined,
          title: '弹幕屏蔽',
          subtitle: '关键词、正则、云屏蔽等级与类型',
          onTap: () => Get.to(() => const DanmakuRuleSubPage()),
        ),
        CfTile(
          icon: Icons.comment_outlined,
          title: '评论屏蔽',
          subtitle: '关键词、带货、@ 数量等',
          onTap: () => Get.to(() => const ReplyRuleSubPage()),
        ),
        CfTile(
          icon: Icons.dynamic_feed_outlined,
          title: '动态屏蔽',
          subtitle: '动态关键词与带货动态',
          onTap: () => Get.to(() => const DynRuleSubPage()),
        ),
        CfTile(
          icon: Icons.ondemand_video_outlined,
          title: '视频屏蔽',
          subtitle: '标题、分区、时长、播放量等',
          onTap: () => Get.to(() => const VideoRuleSubPage()),
        ),
        CfTile(
          icon: Icons.block,
          title: '黑名单',
          subtitle: '屏蔽后其弹幕、评论、动态、视频一并隐藏',
          onTap: () => Get.toNamed('/blackListPage'),
        ),
        CfTile(
          icon: Icons.forum_outlined,
          title: '私信与直播',
          subtitle: '私信里的消息屏蔽词',
          onTap: () => Get.to(() => const MessageRuleSubPage()),
        ),
      ],
    );
  }
}
