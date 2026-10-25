import 'package:PiliPlus/common/widgets/dialog/text_input_dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// AI 提供商设置
///
/// 修改后立即写入，测试连接用的就是当前保存的内容。
/// API Key 只读写存储，不出现在界面与日志里。
class FilterProviderPage extends StatefulWidget {
  const FilterProviderPage({super.key});

  @override
  State<FilterProviderPage> createState() => _FilterProviderPageState();
}

class _FilterProviderPageState extends State<FilterProviderPage> {
  String _baseUrl = Pref.cfApiBaseUrl;
  String _apiKey = Pref.cfApiKey;
  String _model = Pref.cfApiModel;
  int _timeout = Pref.cfApiTimeout;

  bool _testing = false;

  String? _validateUrl(String value) {
    if (value.isEmpty) return '地址不能为空';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      return '地址需以 http:// 或 https:// 开头';
    }
    return null;
  }

  Future<void> _editBaseUrl() async {
    final result = await showTextInputDialog(
      context: context,
      title: '接口地址',
      initialValue: _baseUrl,
      keyboardType: TextInputType.url,
      validator: _validateUrl,
    );
    if (result == null) return;
    Pref.cfApiBaseUrl = result;
    setState(() => _baseUrl = result);
  }

  Future<void> _editApiKey() async {
    final result = await showTextInputDialog(
      context: context,
      title: 'API Key',
      initialValue: _apiKey,
      obscureText: true,
    );
    if (result == null) return;
    Pref.cfApiKey = result;
    setState(() => _apiKey = result);
  }

  Future<void> _editModel() async {
    final result = await showTextInputDialog(
      context: context,
      title: '模型名',
      initialValue: _model,
      validator: (value) => value.isEmpty ? '模型名不能为空' : null,
    );
    if (result == null) return;
    Pref.cfApiModel = result;
    setState(() => _model = result);
  }

  Future<void> _editTimeout() async {
    final result = await showTextInputDialog(
      context: context,
      title: '等待超时',
      initialValue: _timeout.toString(),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      suffixText: '秒',
      validator: (value) {
        final seconds = int.tryParse(value);
        if (seconds == null || seconds < 2 || seconds > 30) {
          return '请输入 2 到 30 之间的秒数';
        }
        return null;
      },
    );
    if (result == null) return;
    final seconds = int.parse(result);
    Pref.cfApiTimeout = seconds;
    setState(() => _timeout = seconds);
  }

  Future<void> _testConnection() async {
    final error = _validateUrl(_baseUrl);
    if (error != null) {
      SmartDialog.showToast(error);
      return;
    }
    if (_apiKey.isEmpty) {
      SmartDialog.showToast('请先填写 API Key');
      return;
    }
    setState(() => _testing = true);
    String message;
    try {
      final result = await JevClient.testConnection(
        endpoint: _baseUrl,
        apiKey: _apiKey,
        model: _model,
        timeout: Duration(seconds: _timeout),
      );
      message = result.message.isEmpty
          ? (result.ok ? '连接成功' : '连接失败')
          : result.message;
      message = message.replaceAll(_apiKey, '***');
    } catch (_) {
      message = '连接失败，请检查接口地址与网络';
    } finally {
      if (mounted) setState(() => _testing = false);
    }
    SmartDialog.showToast(message);
  }

  @override
  Widget build(BuildContext context) {
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
              subtitle: _apiKey.isEmpty ? null : '••••••••',
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
              onTap: _testing ? null : _testConnection,
            ),
          ],
        ),
      ),
    );
  }
}
