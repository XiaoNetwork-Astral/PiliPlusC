import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_tier.dart';
import 'package:PiliPlus/pages/cognitive_filter/ai_tab.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_tab.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 认知滤网首页
///
/// 上面是档位与专业模式，下面是可左右滑动的规则屏蔽与 AI 屏蔽
class CognitiveFilterPage extends StatefulWidget {
  const CognitiveFilterPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<CognitiveFilterPage> createState() => _CognitiveFilterPageState();
}

class _CognitiveFilterPageState extends State<CognitiveFilterPage>
    with SingleTickerProviderStateMixin {
  late FilterTier _tier;
  late bool _proMode;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tier = Pref.cfFilterTier;
    _proMode = Pref.cfFilterProMode;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectTier(FilterTier tier) {
    if (_proMode || _tier == tier) return;
    Pref.cfFilterTier = tier;
    setState(() => _tier = tier);
  }

  void _setProMode(bool value) {
    if (value) {
      CognitiveFilterConfig.enterProMode();
    } else {
      Pref.cfFilterProMode = false;
    }
    setState(() => _proMode = value);
  }

  String _tierDescription(FilterTier tier) {
    return switch (tier) {
      .basic => '只拦辱骂、歧视、低俗、广告，误伤最少',
      .balanced => '再加引战拉踩与阴阳怪气，推荐',
      .strict => '更敏感，误伤更多',
    };
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
              child: Opacity(
                opacity: _proMode ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: _proMode,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final tier in FilterTier.values)
                            _buildTierOption(theme, tier),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CfSwitchTile(
                icon: Icons.tune,
                title: '专业模式',
                value: _proMode,
                onChanged: _setProMode,
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
              AiFilterTab(proMode: _proMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTierOption(ThemeData theme, FilterTier tier) {
    final selected = _tier == tier;
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _selectTier(tier),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tier.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tierDescription(tier),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? foreground.withValues(alpha: 0.8)
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
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
