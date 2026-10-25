import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/common/dm_block_type.dart';
import 'package:PiliPlus/pages/cognitive_filter/danmaku_rule_store.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
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
/// 关键词与正则先在本地编辑并立即生效，需要时再同步到 B 站云端
class DanmakuRuleSubPage extends StatefulWidget {
  const DanmakuRuleSubPage({super.key});

  @override
  State<DanmakuRuleSubPage> createState() => _DanmakuRuleSubPageState();
}

class _DanmakuRuleSubPageState extends State<DanmakuRuleSubPage> {
  String get _blockTypesText {
    final blocked = [
      for (final entry in _blockTypeLabels.entries)
        if (DanmakuOptions.blockTypes.contains(entry.key)) entry.value,
    ];
    return blocked.isEmpty ? '未屏蔽任何类型' : blocked.join('、');
  }

  Future<void> _openList(DmBlockType type) async {
    await Get.to(() => DanmakuRuleListPage(type: type));
    if (mounted) setState(() {});
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

  Future<void> _sync() async {
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('云端同步'),
        children: [
          SimpleDialogOption(
            onPressed: () => Get.back(result: true),
            child: const Text('上传到云端，以本地为准'),
          ),
          SimpleDialogOption(
            onPressed: () => Get.back(result: false),
            child: const Text('从云端下载，覆盖本地'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action) {
      await _push();
    } else {
      await _pull();
    }
  }

  Future<void> _push() async {
    SmartDialog.showLoading(msg: '正在读取云端规则');
    final plan = await DanmakuRuleStore.planPush();
    SmartDialog.dismiss();
    if (plan == null || !mounted) return;
    if (plan.isEmpty) {
      SmartDialog.showToast('本地与云端已经一致');
      return;
    }
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('上传到云端'),
      content: Text('将在云端添加 ${plan.addCount} 条规则，删除 ${plan.deleteCount} 条规则'),
    );
    if (!confirmed) return;
    SmartDialog.showLoading(msg: '正在同步');
    final failed = await DanmakuRuleStore.pushPlan(plan);
    SmartDialog.dismiss();
    SmartDialog.showToast(failed == 0 ? '同步完成' : '同步完成，$failed 条失败');
  }

  Future<void> _pull() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('从云端下载'),
      content: const Text('本地的关键词、正则与弹幕用户规则会被云端内容覆盖'),
    );
    if (!confirmed) return;
    SmartDialog.showLoading(msg: '正在下载');
    final ok = await DanmakuRuleStore.pull();
    SmartDialog.dismiss();
    if (!ok) return;
    SmartDialog.showToast('已用云端规则覆盖本地');
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
              icon: Icons.text_fields,
              title: '关键词屏蔽',
              subtitle: '${DanmakuRuleStore.count(DmBlockType.keyword)} 条',
              onTap: () => _openList(DmBlockType.keyword),
            ),
            CfTile(
              icon: Icons.code,
              title: '正则屏蔽',
              subtitle: '${DanmakuRuleStore.count(DmBlockType.regex)} 条',
              onTap: () => _openList(DmBlockType.regex),
            ),
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
            CfTile(
              icon: Icons.cloud_sync_outlined,
              title: '云端同步',
              subtitle: '与 B 站云端的弹幕屏蔽规则互相同步',
              onTap: _sync,
            ),
          ],
        ),
      ),
    );
  }
}

/// 关键词或正则的本地规则列表
class DanmakuRuleListPage extends StatefulWidget {
  const DanmakuRuleListPage({super.key, required this.type});

  final DmBlockType type;

  @override
  State<DanmakuRuleListPage> createState() => _DanmakuRuleListPageState();
}

class _DanmakuRuleListPageState extends State<DanmakuRuleListPage> {
  DmBlockType get _type => widget.type;

  void _edit([String? old]) {
    var text = old ?? '';
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(old == null ? '添加${_type.label}规则' : '编辑${_type.label}规则'),
        content: TextFormField(
          autofocus: true,
          initialValue: text,
          onChanged: (value) => text = value,
          decoration: InputDecoration(
            hintText: _type == DmBlockType.regex
                ? '输入正则表达式，无需包含头尾的斜杠'
                : '输入要屏蔽的关键词',
          ),
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
            onPressed: () {
              final value = text.trim();
              final error = old == null
                  ? DanmakuRuleStore.add(_type, value)
                  : DanmakuRuleStore.update(_type, old, value);
              if (error != null) {
                SmartDialog.showToast(error);
                return;
              }
              Get.back();
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final list = DanmakuRuleStore.items(_type);
    return SimpleScaffold(
      appBar: AppBar(title: Text('${_type.label}屏蔽')),
      body: ViewSafeArea(
        child: list.isEmpty
            ? Center(
                child: Text(
                  '还没有规则',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.only(bottom: padding.bottom + 100),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  return CfTile(
                    title: item,
                    onTap: () => _edit(item),
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: () => showConfirmDialog(
                        context: context,
                        title: const Text('确定删除该规则？'),
                        onConfirm: () {
                          DanmakuRuleStore.remove(_type, item);
                          setState(() {});
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
      fab: Padding(
        padding: EdgeInsets.only(
          right: kFloatingActionButtonMargin + padding.right,
          bottom: kFloatingActionButtonMargin + padding.bottom,
        ),
        child: FloatingActionButton(
          tooltip: '添加',
          onPressed: _edit,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
