import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// AI 提供商设置
///
/// 目前只接 Jev 判定接口，API Key 只读写存储，不出现在界面与日志里
class FilterProviderPage extends StatefulWidget {
  const FilterProviderPage({super.key});

  @override
  State<FilterProviderPage> createState() => _FilterProviderPageState();
}

class _FilterProviderPageState extends State<FilterProviderPage> {
  late String _baseUrl;
  late String _model;
  late int _timeout;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _baseUrl = Pref.cfApiBaseUrl;
    _model = Pref.cfApiModel;
    _timeout = Pref.cfApiTimeout;
  }

  Future<void> _editBaseUrl() async {
    var value = _baseUrl;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('接口地址'),
        content: TextFormField(
          autofocus: true,
          initialValue: _baseUrl,
          keyboardType: TextInputType.url,
          onChanged: (text) => value = text,
          decoration: const InputDecoration(
            hintText: '以 http 或 https 开头',
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
              final url = value.trim();
              if (!(url.startsWith('http://') ||
                  url.startsWith('https://'))) {
                SmartDialog.showToast('接口地址需以 http 或 https 开头');
                return;
              }
              Get.back(result: url);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    Pref.cfApiBaseUrl = result;
    if (!mounted) return;
    setState(() => _baseUrl = result);
  }

  Future<void> _editApiKey() async {
    var obscure = true;
    var value = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('API Key'),
          content: TextField(
            autofocus: true,
            obscureText: obscure,
            onChanged: (text) => value = text,
            decoration: InputDecoration(
              hintText: Pref.cfApiKey.isEmpty
                  ? '输入 API Key'
                  : '输入新的 API Key，留空则清除',
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setDialogState(() => obscure = !obscure),
              ),
            ),
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
              onPressed: () => Get.back(result: value.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    Pref.cfApiKey = result;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _editModel() async {
    var value = _model;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('模型名'),
        content: TextFormField(
          autofocus: true,
          initialValue: _model,
          onChanged: (text) => value = text,
          decoration: const InputDecoration(hintText: '输入模型名'),
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
              final model = value.trim();
              if (model.isEmpty) {
                SmartDialog.showToast('模型名不能为空');
                return;
              }
              Get.back(result: model);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    Pref.cfApiModel = result;
    if (!mounted) return;
    setState(() => _model = result);
  }

  Future<void> _editTimeout() async {
    var value = _timeout.toString();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('等待超时'),
        content: TextFormField(
          autofocus: true,
          initialValue: value,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (text) => value = text,
          decoration: const InputDecoration(suffixText: '秒'),
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
              final seconds = int.tryParse(value);
              if (seconds == null || seconds < 2 || seconds > 30) {
                SmartDialog.showToast('请输入 2 到 30 之间的秒数');
                return;
              }
              Get.back(result: seconds.toString());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final seconds = int.parse(result);
    Pref.cfApiTimeout = seconds;
    if (!mounted) return;
    setState(() => _timeout = seconds);
  }

  Future<void> _testConnection() async {
    final apiKey = Pref.cfApiKey;
    if (apiKey.isEmpty) {
      SmartDialog.showToast('请先填写 API Key');
      return;
    }

    setState(() => _testing = true);
    try {
      final result = await JevClient.testConnection(
        endpoint: Pref.cfApiBaseUrl,
        apiKey: apiKey,
        model: Pref.cfApiModel,
        timeout: Duration(seconds: Pref.cfApiTimeout),
      );
      if (!mounted) return;
      final message = result.message.isEmpty
          ? (result.ok ? '连接成功' : '连接失败')
          : result.message;
      SmartDialog.showToast(message.replaceAll(apiKey, '***'));
    } catch (_) {
      if (!mounted) return;
      SmartDialog.showToast('测试失败，请检查接口地址与网络');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('AI 提供商')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            CfTile(
              icon: Icons.link,
              title: '接口地址',
              subtitle: _baseUrl,
              onTap: _editBaseUrl,
            ),
            CfTile(
              icon: Icons.key,
              title: 'API Key',
              onTap: _editApiKey,
            ),
            CfTile(
              icon: Icons.memory,
              title: '模型名',
              subtitle: _model,
              onTap: _editModel,
            ),
            CfTile(
              icon: Icons.timer_outlined,
              title: '等待超时',
              subtitle: '$_timeout 秒',
              onTap: _editTimeout,
            ),
            CfTile(
              icon: Icons.wifi_tethering,
              title: '测试连接',
              trailing: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '测试',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
              onTap: _testing ? null : _testConnection,
            ),
          ],
        ),
      ),
    );
  }
}
