import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_tier.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 类别编辑页
///
/// 传入 null 表示新建自定义类别
class CategoryEditPage extends StatefulWidget {
  const CategoryEditPage({super.key, this.category});

  final FilterCategory? category;

  @override
  State<CategoryEditPage> createState() => _CategoryEditPageState();
}

class _CategoryEditPageState extends State<CategoryEditPage> {
  late final String _id;
  late final bool _builtin;
  late final bool _enabled;
  late final TextEditingController _nameController;
  late final TextEditingController _questionController;
  late final TextEditingController _trueController;
  late final TextEditingController _falseController;
  late double _threshold;
  late Set<FilterSurface> _surfaces;

  bool get _isCustom => !_builtin;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _builtin = category?.builtin ?? false;
    _enabled = category?.enabled ?? true;
    _id = category?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';

    final initial =
        category ??
        FilterCategory(
          id: _id,
          name: '自定义类别',
          summary: '自定义类别',
          question: '',
          trueCriteria: '',
          falseCriteria: '',
          threshold: FilterCategory.defaultThreshold,
          enabled: true,
          surfaces: FilterSurface.values.toSet(),
          builtin: false,
        );

    _nameController = TextEditingController(text: initial.name);
    _questionController = TextEditingController(text: initial.question);
    _trueController = TextEditingController(text: initial.trueCriteria);
    _falseController = TextEditingController(text: initial.falseCriteria);
    _threshold = initial.threshold.clamp(0.30, 0.95).toDouble();
    _surfaces = Set<FilterSurface>.of(initial.surfaces);
    if (_surfaces.isEmpty) {
      _surfaces = FilterSurface.values.toSet();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _questionController.dispose();
    _trueController.dispose();
    _falseController.dispose();
    super.dispose();
  }

  String get _title {
    if (!_isCustom) {
      return widget.category?.name ?? '类别规则';
    }
    final name = _nameController.text.trim();
    return name.isEmpty ? '自定义类别' : name;
  }

  void _toggleSurface(FilterSurface surface) {
    if (_surfaces.contains(surface)) {
      if (_surfaces.length == 1) {
        SmartDialog.showToast('至少选择一个应用范围');
        return;
      }
      setState(() => _surfaces.remove(surface));
    } else {
      setState(() => _surfaces.add(surface));
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      SmartDialog.showToast('请填写名称');
      return;
    }
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      SmartDialog.showToast('请填写判定问题');
      return;
    }
    if (_surfaces.isEmpty) {
      SmartDialog.showToast('至少选择一个应用范围');
      return;
    }
    final trueCriteria = _trueController.text.trim();
    final falseCriteria = _falseController.text.trim();

    if (_isCustom) {
      final summary = question.length > 40
          ? question.substring(0, 40)
          : question;
      final category = FilterCategory(
        id: _id,
        name: name,
        summary: summary,
        question: question,
        trueCriteria: trueCriteria,
        falseCriteria: falseCriteria,
        threshold: _threshold,
        enabled: _enabled,
        surfaces: Set<FilterSurface>.of(_surfaces),
        builtin: false,
      );
      final list = Pref.cfCustomCategories.toList();
      final index = list.indexWhere((item) => item.id == _id);
      if (index == -1) {
        list.add(category);
      } else {
        list[index] = category;
      }
      Pref.cfCustomCategories = list;
    } else {
      final factory = builtinCategories.firstWhere((item) => item.id == _id);
      final overrides = Map<String, dynamic>.from(Pref.cfCategoryOverrides);
      final current = <String, dynamic>{};
      final existing = overrides[_id];
      if (existing is Map) {
        current.addAll(Map<String, dynamic>.from(existing));
      }

      if (question == factory.question) {
        current.remove('question');
      } else {
        current['question'] = question;
      }
      if (trueCriteria == factory.trueCriteria) {
        current.remove('trueCriteria');
      } else {
        current['trueCriteria'] = trueCriteria;
      }
      if (falseCriteria == factory.falseCriteria) {
        current.remove('falseCriteria');
      } else {
        current['falseCriteria'] = falseCriteria;
      }
      if (_sameThreshold(_threshold, factory.threshold)) {
        current.remove('threshold');
      } else {
        current['threshold'] = _threshold;
      }
      if (_sameSurfaces(_surfaces, factory.surfaces)) {
        current.remove('surfaces');
      } else {
        current['surfaces'] = [
          for (final surface in FilterSurface.values)
            if (_surfaces.contains(surface)) surface.name,
        ];
      }
      final enabled = current['enabled'];
      if (enabled is bool && enabled == factory.enabled) {
        current.remove('enabled');
      }

      if (current.isEmpty) {
        overrides.remove(_id);
      } else {
        overrides[_id] = current;
      }
      Pref.cfCategoryOverrides = overrides;
    }

    SmartDialog.showToast('已保存');
    Get.back(result: true);
  }

  void _reset() {
    final factory = builtinCategories.firstWhere((item) => item.id == _id);
    CognitiveFilterConfig.resetCategory(_id);
    _questionController.text = factory.question;
    _trueController.text = factory.trueCriteria;
    _falseController.text = factory.falseCriteria;
    setState(() {
      _threshold = factory.threshold.clamp(0.30, 0.95).toDouble();
      _surfaces = Set<FilterSurface>.of(factory.surfaces);
    });
    SmartDialog.showToast('已恢复默认');
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('删除这个类别'),
      content: const Text('删除后无法恢复'),
    );
    if (!confirmed) return;
    final list = Pref.cfCustomCategories
        .where((item) => item.id != _id)
        .toList();
    Pref.cfCustomCategories = list;
    SmartDialog.showToast('已删除');
    Get.back(result: true);
  }

  bool _sameThreshold(double value, double other) =>
      (value - other).abs() < 0.0001;

  bool _sameSurfaces(Set<FilterSurface> value, Set<FilterSurface> other) =>
      value.length == other.length && value.containsAll(other);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ViewSafeArea(
        child: ViewInsetsSafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
            children: [
              TextField(
                controller: _nameController,
                readOnly: !_isCustom,
                onChanged: _isCustom ? (_) => setState(() {}) : null,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _questionController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '判定问题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _trueController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '算作是'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _falseController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '算作否'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('屏蔽阈值', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    _threshold.toStringAsFixed(2),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _threshold,
                min: 0.30,
                max: 0.95,
                divisions: 65,
                label: _threshold.toStringAsFixed(2),
                onChanged: (value) => setState(() => _threshold = value),
              ),
              Row(
                children: [
                  Text(
                    '灵敏度',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  for (final sensitivity in FilterSensitivity.values) ...[
                    _sensitivityButton(sensitivity),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Text('应用于', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final surface in FilterSurface.values)
                    _surfaceButton(surface),
                ],
              ),
              const SizedBox(height: 28),
              if (_builtin)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复默认'),
                  ),
                ),
              if (_isCustom)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sensitivityButton(FilterSensitivity sensitivity) {
    final selected = (_threshold - sensitivity.threshold).abs() < 0.001;
    void onPressed() {
      setState(() {
        _threshold = sensitivity.threshold.clamp(0.30, 0.95).toDouble();
      });
    }

    if (selected) {
      return FilledButton.tonal(
        onPressed: onPressed,
        child: Text(sensitivity.label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(sensitivity.label),
    );
  }

  Widget _surfaceButton(FilterSurface surface) {
    final selected = _surfaces.contains(surface);
    void onPressed() => _toggleSurface(surface);

    if (selected) {
      return FilledButton.tonal(
        onPressed: onPressed,
        child: Text(surface.label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(surface.label),
    );
  }
}
