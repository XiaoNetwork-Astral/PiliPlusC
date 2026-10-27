import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/ai_tab.dart';
import 'package:PiliPlus/pages/cognitive_filter/judge_history_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_tab.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_service.dart';
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
    CalibrationService.instance.enterSettings();
  }

  @override
  void dispose() {
    CalibrationService.instance.leaveSettings();
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
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('认知滤网'),
              actions: [
                IconButton(
                  tooltip: '清零统计',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: _resetStats,
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: ViewSafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: ValueListenableBuilder<int>(
                valueListenable: BlockStats.instance.version,
                builder: (context, _, __) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.showAppBar)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: '清零统计',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.restart_alt),
                            onPressed: _resetStats,
                          ),
                        ),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _StatCard(
                                value: '${BlockStats.instance.total}',
                                label: '累计屏蔽',
                                unit: '条',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                value: '${BlockStats.instance.days}',
                                label: '已过滤',
                                unit: '天',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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

/// 首页统计用的数字卡片，不可点击
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.unit,
  });

  final String value;
  final String label;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(width: 4),
                Text(unit, style: theme.textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
