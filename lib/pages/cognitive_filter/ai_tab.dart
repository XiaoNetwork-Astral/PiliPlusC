import 'package:PiliPlus/common/widgets/dialog/text_input_dialog.dart';
import 'package:PiliPlus/pages/cognitive_filter/category_list_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/judge_trial_dialog.dart';
import 'package:PiliPlus/pages/cognitive_filter/provider_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// AI 屏蔽页
///
/// 对规则屏蔽后的内容再交给 Jev 二次判断
class AiFilterTab extends StatefulWidget {
  const AiFilterTab({super.key, required this.proMode});

  final bool proMode;

  @override
  State<AiFilterTab> createState() => _AiFilterTabState();
}

class _AiFilterTabState extends State<AiFilterTab> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = Pref.cfAiFilterEnabled;
  }

  Future<void> _toggle(bool value) async {
    if (!value) {
      Pref.cfAiFilterEnabled = false;
      setState(() => _enabled = false);
      return;
    }

    if (Pref.cfApiKey.isEmpty) {
      SmartDialog.showToast('请先在 AI 提供商中填写 API Key');
    }

    final rawAccepted = GStorage.setting.get(
      SettingBoxKey.cfAiPrivacyAccepted,
      defaultValue: false,
    );
    final accepted = rawAccepted is bool ? rawAccepted : false;
    if (!accepted) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('开启 AI 屏蔽'),
              content: const Text('开启后，弹幕、评论、动态、视频的文字会发送到你配置的服务'),
              actions: [
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: ColorScheme.of(dialogContext).outline,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Get.back(result: true),
                  child: const Text('我已了解并开启'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
      await GStorage.setting.put(
        SettingBoxKey.cfAiPrivacyAccepted,
        true,
      );
    }

    Pref.cfAiFilterEnabled = true;
    if (!mounted) return;
    setState(() => _enabled = true);
  }

  Future<void> _openProvider() async {
    await Get.to(() => const FilterProviderPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _editDailyCap() async {
    final cap = Pref.cfAiDailyCapUsd;
    final result = await showTextInputDialog(
      context: context,
      title: '每日用量上限',
      initialValue: cap > 0 ? _formatUsd(cap) : '0',
      hintText: '0 表示不限制',
      suffixText: '美元',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        final number = double.tryParse(value);
        if (number == null || !number.isFinite || number < 0) {
          return '请输入不小于 0 的数字';
        }
        return null;
      },
    );
    if (result == null) return;
    Pref.cfAiDailyCapUsd = double.parse(result);
    if (!mounted) return;
    setState(() {});
  }

  String _formatUsd(double value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Future<void> _openCategories() async {
    await Get.to(() => const CategoryRulesPage());
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return ListView(
      primary: true,
      key: const PageStorageKey<String>('cfAiList'),
      padding: EdgeInsets.only(bottom: bottomPadding),
      children: [
        CfSwitchTile(
          icon: Icons.auto_awesome_outlined,
          title: '启用 AI 屏蔽',
          value: _enabled,
          onChanged: _toggle,
        ),
        CfTile(
          icon: Icons.dns_outlined,
          title: 'AI 提供商',
          onTap: _openProvider,
        ),
        CfTile(
          icon: Icons.savings_outlined,
          title: '每日用量上限',
          subtitle: '今日已用 \$${AiFilterRuntime.instance.usdToday.toStringAsFixed(3)}',
          trailing: Text(
            Pref.cfAiDailyCapUsd > 0
                ? '\$${_formatUsd(Pref.cfAiDailyCapUsd)}'
                : '不限制',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          onTap: _editDailyCap,
        ),
        if (widget.proMode) ...[
          CfTile(
            icon: Icons.category_outlined,
            title: '类别规则',
            subtitle: '调整每个类别的开关、阈值与适用面',
            onTap: _openCategories,
          ),
          CfTile(
            icon: Icons.science_outlined,
            title: '试判定',
            onTap: () => showJudgeTrialDialog(context),
          ),
        ],
      ],
    );
  }
}
