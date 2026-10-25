import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/pages/cognitive_filter/category_edit_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 类别规则列表
///
/// 只在专业模式下使用，列出当前生效的类别
class CategoryRulesPage extends StatefulWidget {
  const CategoryRulesPage({super.key});

  @override
  State<CategoryRulesPage> createState() => _CategoryRulesPageState();
}

class _CategoryRulesPageState extends State<CategoryRulesPage> {
  late List<FilterCategory> _categories;

  @override
  void initState() {
    super.initState();
    _categories = CognitiveFilterConfig.effectiveCategories;
  }

  void _reload() {
    setState(() {
      _categories = CognitiveFilterConfig.effectiveCategories;
    });
  }

  Future<void> _openEdit([FilterCategory? category]) async {
    await Get.to(
      () => CategoryEditPage(category: category),
    );
    if (!mounted) return;
    _reload();
  }

  void _toggle(FilterCategory category, bool value) {
    if (category.builtin) {
      final overrides = Map<String, dynamic>.from(Pref.cfCategoryOverrides);
      final raw = overrides[category.id];
      final current = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      current['enabled'] = value;
      overrides[category.id] = current;
      Pref.cfCategoryOverrides = overrides;
    } else {
      final list = Pref.cfCustomCategories;
      final index = list.indexWhere((item) => item.id == category.id);
      if (index == -1) return;
      final updated = list.toList()
        ..[index] = list[index].copyWith(enabled: value);
      Pref.cfCustomCategories = updated;
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('类别规则')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            const CfHint('开关与阈值只影响 AI 屏蔽，规则屏蔽不受影响'),
            for (final category in _categories)
              CfTile(
                title: category.name,
                subtitle: category.id == 'mock'
                    ? '${category.summary}，误伤偏高'
                    : category.summary,
                trailing: Transform.scale(
                  scale: 0.8,
                  alignment: Alignment.centerRight,
                  child: Switch(
                    value: category.enabled,
                    onChanged: (value) => _toggle(category, value),
                  ),
                ),
                onTap: () => _openEdit(category),
              ),
            CfTile(
              icon: Icons.add,
              title: '添加自定义类别',
              onTap: _openEdit,
            ),
          ],
        ),
      ),
    );
  }
}
