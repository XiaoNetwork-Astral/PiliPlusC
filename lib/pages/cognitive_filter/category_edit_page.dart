import 'package:PiliPlus/common/widgets/dialog/text_input_dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/builtin_categories.dart';
import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
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
  late String _name;
  late String _question;
  late String _trueCriteria;
  late String _falseCriteria;
  late double _threshold;
  late Set<FilterSurface> _surfaces;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _builtin = category?.builtin ?? false;
    _enabled = category?.enabled ?? true;
    _id = category?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _name = category?.name ?? '自定义类别';
    _question = category?.question ?? '';
    _trueCriteria = category?.trueCriteria ?? '';
    _falseCriteria = category?.falseCriteria ?? '';
    _threshold = (category?.threshold ?? FilterCategory.defaultThreshold)
        .clamp(0.30, 0.95)
        .toDouble();
    _surfaces = Set<FilterSurface>.of(
      category?.surfaces ?? FilterSurface.values,
    );
    if (_surfaces.isEmpty) {
      _surfaces = FilterSurface.values.toSet();
    }
  }

  String get _surfacesText => [
    for (final surface in FilterSurface.values)
      if (_surfaces.contains(surface)) surface.label,
  ].join('、');

  /// 修改后立即写入。新建的自定义类别要等判定问题填写后才会真正创建
  void _persist() {
    if (_question.isEmpty) return;
    if (!_builtin) {
      final summary = _question.length > 40
          ? _question.substring(0, 40)
          : _question;
      final category = FilterCategory(
        id: _id,
        name: _name,
        summary: summary,
        question: _question,
        trueCriteria: _trueCriteria,
        falseCriteria: _falseCriteria,
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
      return;
    }

    final factory = builtinCategories.firstWhere((item) => item.id == _id);
    final overrides = Map<String, dynamic>.from(Pref.cfCategoryOverrides);
    final current = <String, dynamic>{};
    final existing = overrides[_id];
    if (existing is Map) {
      current.addAll(Map<String, dynamic>.from(existing));
    }

    if (_question == factory.question) {
      current.remove('question');
    } else {
      current['question'] = _question;
    }
    if (_trueCriteria == factory.trueCriteria) {
      current.remove('trueCriteria');
    } else {
      current['trueCriteria'] = _trueCriteria;
    }
    if (_falseCriteria == factory.falseCriteria) {
      current.remove('falseCriteria');
    } else {
      current['falseCriteria'] = _falseCriteria;
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

  Future<void> _editName() async {
    final result = await showTextInputDialog(
      context: context,
      title: '名称',
      initialValue: _name,
      validator: (value) => value.isEmpty ? '名称不能为空' : null,
    );
    if (result == null) return;
    setState(() => _name = result);
    _persist();
  }

  Future<void> _editQuestion() async {
    final result = await showTextInputDialog(
      context: context,
      title: '判定问题',
      initialValue: _question,
      maxLines: 8,
      validator: (value) => value.isEmpty ? '判定问题不能为空' : null,
    );
    if (result == null) return;
    setState(() => _question = result);
    _persist();
  }

  Future<void> _editTrueCriteria() async {
    final result = await showTextInputDialog(
      context: context,
      title: '算作是',
      initialValue: _trueCriteria,
      maxLines: 8,
    );
    if (result == null) return;
    setState(() => _trueCriteria = result);
    _persist();
  }

  Future<void> _editFalseCriteria() async {
    final result = await showTextInputDialog(
      context: context,
      title: '算作否',
      initialValue: _falseCriteria,
      maxLines: 8,
    );
    if (result == null) return;
    setState(() => _falseCriteria = result);
    _persist();
  }

  Future<void> _editThreshold() async {
    var value = _threshold;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('屏蔽阈值'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value.toStringAsFixed(2)),
              Slider(
                min: 0.30,
                max: 0.95,
                divisions: 13,
                value: value,
                label: value.toStringAsFixed(2),
                onChanged: (v) => setDialogState(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(dialogContext).pop,
              child: Text(
                '取消',
                style: TextStyle(color: ColorScheme.of(dialogContext).outline),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _threshold = result);
    _persist();
  }

  Future<void> _editSurfaces() async {
    final result = await showDialog<Set<FilterSurface>>(
      context: context,
      builder: (context) => MultiSelectDialog<FilterSurface>(
        title: '应用于',
        initValues: _surfaces,
        values: {
          for (final surface in FilterSurface.values) surface: surface.label,
        },
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      SmartDialog.showToast('至少选择一个应用范围');
      return;
    }
    setState(() => _surfaces = result);
    _persist();
  }

  void _reset() {
    final factory = builtinCategories.firstWhere((item) => item.id == _id);
    CognitiveFilterConfig.resetCategory(_id);
    setState(() {
      _question = factory.question;
      _trueCriteria = factory.trueCriteria;
      _falseCriteria = factory.falseCriteria;
      _threshold = factory.threshold.clamp(0.30, 0.95).toDouble();
      _surfaces = Set<FilterSurface>.of(factory.surfaces);
    });
  }

  bool _sameThreshold(double value, double other) =>
      (value - other).abs() < 0.0001;

  bool _sameSurfaces(Set<FilterSurface> value, Set<FilterSurface> other) =>
      value.length == other.length && value.containsAll(other);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: Text(_builtin ? _name : '自定义类别')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            if (!_builtin)
              CfTile(
                icon: Icons.label_outline,
                title: '名称',
                subtitle: _name,
                onTap: _editName,
              ),
            CfTile(
              icon: Icons.help_outline,
              title: '判定问题',
              subtitle: _question.isEmpty ? '未填写' : _question,
              subtitleMaxLines: 2,
              onTap: _editQuestion,
            ),
            CfTile(
              icon: Icons.check_circle_outline,
              title: '算作是',
              subtitle: _trueCriteria.isEmpty ? '未填写' : _trueCriteria,
              subtitleMaxLines: 2,
              onTap: _editTrueCriteria,
            ),
            CfTile(
              icon: Icons.highlight_off,
              title: '算作否',
              subtitle: _falseCriteria.isEmpty ? '未填写' : _falseCriteria,
              subtitleMaxLines: 2,
              onTap: _editFalseCriteria,
            ),
            CfTile(
              icon: Icons.tune,
              title: '屏蔽阈值',
              subtitle: _threshold.toStringAsFixed(2),
              onTap: _editThreshold,
            ),
            CfTile(
              icon: Icons.apps,
              title: '应用于',
              subtitle: _surfacesText,
              onTap: _editSurfaces,
            ),
            if (_builtin)
              CfTile(
                icon: Icons.restore,
                title: '恢复默认',
                onTap: _reset,
              ),
          ],
        ),
      ),
    );
  }
}
