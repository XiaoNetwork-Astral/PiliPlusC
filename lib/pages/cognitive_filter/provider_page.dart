import 'package:PiliPlus/common/widgets/dialog/text_input_dialog.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/backup/widgets/backup_dialogs.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// AI 提供商设置
///
/// 先在页面里修改，测试连接用的是当前填写的内容，点保存才会写入。
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

  String _savedBaseUrl = Pref.cfApiBaseUrl;
  String _savedApiKey = Pref.cfApiKey;
  String _savedModel = Pref.cfApiModel;
  int _savedTimeout = Pref.cfApiTimeout;

  bool _testing = false;

  bool get _dirty =>
      _baseUrl != _savedBaseUrl ||
      _apiKey != _savedApiKey ||
      _model != _savedModel ||
      _timeout != _savedTimeout;

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
    if (result != null) setState(() => _baseUrl = result);
  }

  Future<void> _editApiKey() async {
    final result = await showTextInputDialog(
      context: context,
      title: 'API Key',
      initialValue: _apiKey,
      obscureText: true,
    );
    if (result != null) setState(() => _apiKey = result);
  }

  Future<void> _editModel() async {
    final result = await showTextInputDialog(
      context: context,
      title: '模型名',
      initialValue: _model,
      validator: (value) => value.isEmpty ? '模型名不能为空' : null,
    );
    if (result != null) setState(() => _model = result);
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
    if (result != null) setState(() => _timeout = int.parse(result));
  }

  void _save() {
    Pref.cfApiBaseUrl = _baseUrl;
    Pref.cfApiKey = _apiKey;
    Pref.cfApiModel = _model;
    Pref.cfApiTimeout = _timeout;
    setState(() {
      _savedBaseUrl = _baseUrl;
      _savedApiKey = _apiKey;
      _savedModel = _model;
      _savedTimeout = _timeout;
    });
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

  Future<void> _onBack() async {
    final discard = await showUnsavedChangesDialog(context);
    if (!discard || !mounted) return;
    setState(() {
      _savedBaseUrl = _baseUrl;
      _savedApiKey = _apiKey;
      _savedModel = _model;
      _savedTimeout = _timeout;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Get.back();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return popScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack();
      },
      child: SimpleScaffold(
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
                enabled: !_testing,
                trailing: _testing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _testConnection,
              ),
              CfTile(
                icon: Icons.save_outlined,
                title: '保存',
                enabled: _dirty,
                onTap: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
