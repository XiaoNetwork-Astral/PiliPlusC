import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/ai_tab.dart';
import 'package:PiliPlus/pages/cognitive_filter/judge_history_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_tab.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/block_stats.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 认知滤网首页
///
/// 上面是屏蔽统计与屏蔽历史，下面是可左右滑动的规则屏蔽与 AI 屏蔽
class CognitiveFilterPage extends StatefulWidget {
  const CognitiveFilterPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<CognitiveFilterPage> createState() => _CognitiveFilterPageState();
}

class _CognitiveFilterPageState extends State<CognitiveFilterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _resetStats() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定清零屏蔽统计？'),
    );
    if (!confirmed) return;
    BlockStats.instance.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('认知滤网')) : null,
      body: ViewSafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: ValueListenableBuilder<int>(
                valueListenable: BlockStats.instance.version,
                builder: (context, _, __) => CfTile(
                  icon: Icons.shield_outlined,
                  title: '累计屏蔽 ${BlockStats.instance.total} 条',
                  trailing: Text(
                    '已过滤 ${BlockStats.instance.days} 天',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CfTile(
                icon: Icons.restart_alt,
                title: '清零统计',
                onTap: _resetStats,
              ),
            ),
            SliverToBoxAdapter(
              child: CfTile(
                icon: Icons.history,
                title: '屏蔽历史',
                onTap: () => Get.to(() => const JudgeHistoryPage()),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeaderDelegate(
                tabBar: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: '规则屏蔽'),
                    Tab(text: 'AI 屏蔽'),
                  ],
                ),
                color: theme.colorScheme.surface,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              const RuleFilterTab(),
              const AiFilterTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarHeaderDelegate({required this.tabBar, required this.color});

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(color: color, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar || color != oldDelegate.color;
  }
}
