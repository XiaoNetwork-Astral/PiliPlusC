import 'package:PiliPlus/pages/cognitive_filter/danmaku_block_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_list_page.dart';
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

  Future<void> _open(Widget Function() page) async {
    await Get.to(page);
    if (mounted) setState(() {});
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
          value: _enabled,
          onChanged: _toggle,
        ),
        CfTile(
          icon: Icons.rule,
          title: '屏蔽规则',
          onTap: () => _open(() => const RuleListPage()),
        ),
        CfTile(
          icon: Icons.subtitles_outlined,
          title: '弹幕屏蔽',
          subtitle: '智能云屏蔽等级、按类型屏蔽',
          onTap: () => _open(() => const DanmakuBlockSubPage()),
        ),
        CfTile(
          icon: Icons.comment_outlined,
          title: '评论屏蔽',
          subtitle: '带货、@ 数量、复制简介等',
          onTap: () => _open(() => const ReplyRuleSubPage()),
        ),
        CfTile(
          icon: Icons.dynamic_feed_outlined,
          title: '动态屏蔽',
          subtitle: '带货动态',
          onTap: () => _open(() => const DynRuleSubPage()),
        ),
        CfTile(
          icon: Icons.ondemand_video_outlined,
          title: '视频屏蔽',
          subtitle: '点赞率、时长、播放量等',
          onTap: () => _open(() => const VideoRuleSubPage()),
        ),
      ],
    );
  }
}
