import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/pages/cognitive_filter/ai_surface_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/category_list_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/provider_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_list_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_core.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// AI 屏蔽页
///
/// 对规则屏蔽后的内容再交给 Jev 二次判断
class AiFilterTab extends StatefulWidget {
  const AiFilterTab({super.key});

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

  bool get _hasProvider =>
      Pref.cfApiKey.trim().isNotEmpty &&
      Pref.cfApiBaseUrl.trim().isNotEmpty &&
      Pref.cfApiModel.trim().isNotEmpty;

  Future<void> _toggle(bool value) async {
    if (!value) {
      Pref.cfAiFilterEnabled = false;
      setState(() => _enabled = false);
      return;
    }

    // 每次打开都确认，不记住上一次的选择
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('开启 AI 屏蔽'),
            content: const Text(
              '开启后，弹幕、评论、动态、视频标题等文字会发送到你配置的外部 AI 服务来判断是否屏蔽\n\n'
              '使用校准向导时，还会把其中一部分内容发送到你配置的整理服务',
            ),
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

    Pref.cfAiFilterEnabled = true;
    if (!mounted) return;
    setState(() => _enabled = true);
  }

  Future<void> _openProvider() async {
    await Get.to(() => const FilterProviderPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _clearCache() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定清除 AI 判定缓存？'),
    );
    if (!confirmed) return;
    await AiFilterRuntime.instance.clearCache();
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
          enabled: _enabled || _hasProvider,
          onDisabledTap: () => SmartDialog.showToast('请先填写 AI 提供商'),
        ),
        CfTile(
          icon: Icons.dns_outlined,
          title: 'AI 提供商',
          onTap: _openProvider,
        ),
        CfTile(
          icon: Icons.category_outlined,
          title: '类别规则',
          onTap: _openCategories,
        ),
        CfTile(
          icon: Icons.apps,
          title: '生效范围',
          onTap: () => Get.to(() => const AiSurfacePage()),
        ),
        CfTile(
          icon: Icons.verified_user_outlined,
          title: '白名单',
          onTap: () => Get.to(
            () => RuleListPage(
              source: AiWhitelist.instance,
              title: '白名单',
              allowedScopes: aiWhitelistScopes,
            ),
          ),
        ),
        CfTile(
          icon: Icons.cleaning_services_outlined,
          title: '清除缓存',
          onTap: _clearCache,
        ),
      ],
    );
  }
}
