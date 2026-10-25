import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const _blockTypeLabels = {
  2: '滚动',
  5: '顶部',
  4: '底部',
  6: '彩色',
  7: '高级',
};

/// 弹幕屏蔽
///
/// 关键词、正则与用户已并入「规则」，这里只留与规则无关的两项播放器设置
class DanmakuBlockSubPage extends StatefulWidget {
  const DanmakuBlockSubPage({super.key});

  @override
  State<DanmakuBlockSubPage> createState() => _DanmakuBlockSubPageState();
}

class _DanmakuBlockSubPageState extends State<DanmakuBlockSubPage> {
  String get _blockTypesText {
    final blocked = [
      for (final entry in _blockTypeLabels.entries)
        if (DanmakuOptions.blockTypes.contains(entry.key)) entry.value,
    ];
    return blocked.isEmpty ? '未屏蔽任何类型' : blocked.join('、');
  }

  Future<void> _editWeight() async {
    var value = DanmakuOptions.danmakuWeight.toDouble();
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('智能云屏蔽等级'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value == 0 ? '不按等级屏蔽' : '屏蔽等级低于 ${value.toInt()} 级的弹幕',
              ),
              Slider(
                min: 0,
                max: 11,
                divisions: 11,
                value: value,
                label: value.toInt().toString(),
                onChanged: (v) => setDialogState(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: ColorScheme.of(dialogContext).outline),
              ),
            ),
            TextButton(
              onPressed: () => Get.back(result: value.toInt()),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    DanmakuOptions.danmakuWeight = result;
    await GStorage.setting.put(SettingBoxKey.danmakuWeight, result);
    if (mounted) setState(() {});
  }

  Future<void> _editBlockTypes() async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => MultiSelectDialog<int>(
        title: '按类型屏蔽',
        initValues: DanmakuOptions.blockTypes,
        values: _blockTypeLabels,
      ),
    );
    if (result == null) return;
    DanmakuOptions.blockTypes
      ..clear()
      ..addAll(result);
    DanmakuOptions.blockColorful = result.contains(6);
    await GStorage.setting.put(SettingBoxKey.danmakuBlockType, result.toList());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('弹幕屏蔽')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            CfTile(
              icon: Icons.speed,
              title: '智能云屏蔽等级',
              subtitle: DanmakuOptions.danmakuWeight == 0
                  ? '不按等级屏蔽'
                  : '${DanmakuOptions.danmakuWeight} 级',
              onTap: _editWeight,
            ),
            CfTile(
              icon: Icons.view_agenda_outlined,
              title: '按类型屏蔽',
              subtitle: _blockTypesText,
              onTap: _editBlockTypes,
            ),
          ],
        ),
      ),
    );
  }
}
