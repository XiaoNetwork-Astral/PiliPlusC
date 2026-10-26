import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
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
/// 列出当前生效的类别
class CategoryRulesPage extends StatefulWidget {
  const CategoryRulesPage({super.key});

  @override
  State<CategoryRulesPage> createState() => _CategoryRulesPageState();
}

class _CategoryRulesPageState extends State<CategoryRulesPage> {
  late List<FilterCategory> _categories;
  late double _threshold;

  @override
  void initState() {
    super.initState();
    _categories = CognitiveFilterConfig.effectiveCategories;
    _threshold = Pref.cfProThreshold;
  }

  /// 敏感度 0 到 100，阈值越低越敏感
  int get _sensitivityPercent => ((0.95 - _threshold) / 0.65 * 100).round();

  void _onSensitivityChanged(double value) {
    setState(() => _threshold = 1.25 - value);
  }

  void _onSensitivityChangeEnd(double value) {
    Pref.cfProThreshold = 1.25 - value;
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

  Future<void> _delete(FilterCategory category) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定删除该类别？'),
    );
    if (!confirmed) return;
    Pref.cfCustomCategories = Pref.cfCustomCategories
        .where((item) => item.id != category.id)
        .toList();
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
            CfTile(
              icon: Icons.tune,
              title: '敏感度',
              trailing: Text(
                '$_sensitivityPercent%',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Slider(
                min: 0.30,
                max: 0.95,
                divisions: 13,
                value: (1.25 - _threshold).clamp(0.30, 0.95).toDouble(),
                label: '$_sensitivityPercent%',
                onChanged: _onSensitivityChanged,
                onChangeEnd: _onSensitivityChangeEnd,
              ),
            ),
            for (final category in _categories)
              CfTile(
                contentPadding: const EdgeInsetsDirectional.only(
                  start: 16,
                  end: 12,
                ),
                title: category.name,
                subtitle: category.id == 'mock'
                    ? '${category.summary}，误伤偏高'
                    : category.summary,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!category.builtin)
                      IconButton(
                        tooltip: '删除',
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _delete(category),
                      ),
                    Transform.scale(
                      scale: 0.8,
                      alignment: Alignment.centerRight,
                      child: Switch(
                        value: category.enabled,
                        onChanged: (value) => _toggle(category, value),
                      ),
                    ),
                  ],
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
