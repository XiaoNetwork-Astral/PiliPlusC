import 'package:PiliPlus/common/widgets/dialog/text_input_dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_runtime.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/jev_proxy.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 一个接口（判定或整理）的可编辑设置，读写都直接落到存储
class _EndpointStore {
  const _EndpointStore({
    required this.getBaseUrl,
    required this.setBaseUrl,
    required this.getApiKey,
    required this.setApiKey,
    required this.getModel,
    required this.setModel,
    required this.getProxyType,
    required this.setProxyType,
    required this.getProxyAddress,
    required this.setProxyAddress,
  });

  final String Function() getBaseUrl;
  final void Function(String) setBaseUrl;
  final String Function() getApiKey;
  final void Function(String) setApiKey;
  final String Function() getModel;
  final void Function(String) setModel;
  final int Function() getProxyType;
  final void Function(int) setProxyType;
  final String Function() getProxyAddress;
  final void Function(String) setProxyAddress;

  JevProxy? get proxy => JevProxy.parse(
    JevProxyType.values[getProxyType().clamp(0, JevProxyType.values.length - 1)],
    getProxyAddress(),
  );
}

final _EndpointStore _judgeStore = _EndpointStore(
  getBaseUrl: () => Pref.cfApiBaseUrl,
  setBaseUrl: (value) => Pref.cfApiBaseUrl = value,
  getApiKey: () => Pref.cfApiKey,
  setApiKey: (value) => Pref.cfApiKey = value,
  getModel: () => Pref.cfApiModel,
  setModel: (value) => Pref.cfApiModel = value,
  getProxyType: () => Pref.cfApiProxyType,
  setProxyType: (value) => Pref.cfApiProxyType = value,
  getProxyAddress: () => Pref.cfApiProxyAddress,
  setProxyAddress: (value) => Pref.cfApiProxyAddress = value,
);

final _EndpointStore _llmStore = _EndpointStore(
  getBaseUrl: () => Pref.cfLlmBaseUrl,
  setBaseUrl: (value) => Pref.cfLlmBaseUrl = value,
  getApiKey: () => Pref.cfLlmApiKey,
  setApiKey: (value) => Pref.cfLlmApiKey = value,
  getModel: () => Pref.cfLlmModel,
  setModel: (value) => Pref.cfLlmModel = value,
  getProxyType: () => Pref.cfLlmProxyType,
  setProxyType: (value) => Pref.cfLlmProxyType = value,
  getProxyAddress: () => Pref.cfLlmProxyAddress,
  setProxyAddress: (value) => Pref.cfLlmProxyAddress = value,
);

/// AI 提供商设置：判定接口、整理接口与通用项
///
/// 修改后立即写入，测试连接用的就是当前保存的内容。
/// API Key 只读写存储，不出现在界面与日志里。
class FilterProviderPage extends StatefulWidget {
  const FilterProviderPage({super.key});

  @override
  State<FilterProviderPage> createState() => _FilterProviderPageState();
}

class _FilterProviderPageState extends State<FilterProviderPage> {
  int _timeout = Pref.cfApiTimeout;

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

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('AI 提供商')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            const CfGroupHeader('判定接口'),
            _EndpointSection(
              store: _judgeStore,
              test: _testJudge,
            ),
            const CfGroupHeader('整理接口'),
            _EndpointSection(
              store: _llmStore,
              test: _testLlm,
            ),
            const CfGroupHeader('通用'),
            CfTile(
              icon: Icons.timer_outlined,
              title: '等待超时',
              subtitle: '$_timeout 秒',
              onTap: _editTimeout,
            ),
            CfTile(
              icon: Icons.savings_outlined,
              title: '每日用量上限',
              subtitle:
                  '今日已用 \$${AiFilterRuntime.instance.usdToday.toStringAsFixed(3)}',
              trailing: Text(
                Pref.cfAiDailyCapUsd > 0
                    ? '\$${_formatUsd(Pref.cfAiDailyCapUsd)}'
                    : '不限制',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              onTap: _editDailyCap,
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _testJudge() async {
    final store = _judgeStore;
    final apiKey = store.getApiKey();
    try {
      final result = await JevClient.testConnection(
        endpoint: store.getBaseUrl(),
        apiKey: apiKey,
        model: store.getModel(),
        timeout: Duration(seconds: _timeout),
        proxy: store.proxy,
      );
      final message = result.message.isEmpty
          ? (result.ok ? '连接成功' : '连接失败')
          : result.message;
      return message.replaceAll(apiKey, '***');
    } catch (_) {
      return '连接失败，请检查接口地址与网络';
    }
  }

  Future<String> _testLlm() async {
    final store = _llmStore;
    try {
      await LlmClient(
        baseUrl: store.getBaseUrl(),
        apiKey: store.getApiKey(),
        model: store.getModel(),
        timeout: const Duration(seconds: 30),
        proxy: store.proxy,
      ).test();
      return '连接成功';
    } on LlmException catch (error) {
      return llmErrorText(error.kind);
    } catch (_) {
      return '连接失败，请检查接口地址与网络';
    }
  }
}

/// 一个接口的五项设置加测试按钮
class _EndpointSection extends StatefulWidget {
  const _EndpointSection({required this.store, required this.test});

  final _EndpointStore store;

  /// 用当前保存的设置测试连接，返回要提示给用户的一句话
  final Future<String> Function() test;

  @override
  State<_EndpointSection> createState() => _EndpointSectionState();
}

class _EndpointSectionState extends State<_EndpointSection> {
  static const List<(int, String)> _proxyTypes = [
    (0, '不使用'),
    (1, 'HTTP'),
    (2, 'SOCKS5'),
  ];

  bool _testing = false;

  _EndpointStore get _store => widget.store;

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
      initialValue: _store.getBaseUrl(),
      keyboardType: TextInputType.url,
      validator: _validateUrl,
    );
    if (result == null) return;
    _store.setBaseUrl(result);
    setState(() {});
  }

  Future<void> _editApiKey() async {
    final result = await showTextInputDialog(
      context: context,
      title: 'API Key',
      initialValue: _store.getApiKey(),
      obscureText: true,
    );
    if (result == null) return;
    _store.setApiKey(result);
    setState(() {});
  }

  Future<void> _editModel() async {
    final result = await showTextInputDialog(
      context: context,
      title: '模型名',
      initialValue: _store.getModel(),
      validator: (value) => value.isEmpty ? '模型名不能为空' : null,
    );
    if (result == null) return;
    _store.setModel(result);
    setState(() {});
  }

  Future<void> _editProxyType() async {
    final current = _store.getProxyType();
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SelectDialog<int>(
        title: '代理类型',
        value: current,
        values: _proxyTypes,
      ),
    );
    if (result == null || result == current) return;
    _store.setProxyType(result);
    setState(() {});
  }

  Future<void> _editProxyAddress() async {
    final result = await showTextInputDialog(
      context: context,
      title: '代理地址',
      hintText: '127.0.0.1:7890',
      initialValue: _store.getProxyAddress(),
      validator: (value) {
        if (value.isEmpty) return null;
        return JevProxy.parse(JevProxyType.http, value) == null
            ? '请填写 地址:端口'
            : null;
      },
    );
    if (result == null) return;
    _store.setProxyAddress(result);
    setState(() {});
  }

  Future<void> _testConnection() async {
    final error = _validateUrl(_store.getBaseUrl());
    if (error != null) {
      SmartDialog.showToast(error);
      return;
    }
    if (_store.getApiKey().isEmpty) {
      SmartDialog.showToast('请先填写 API Key');
      return;
    }
    setState(() => _testing = true);
    String message;
    try {
      message = await widget.test();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
    SmartDialog.showToast(message);
  }

  @override
  Widget build(BuildContext context) {
    final proxyType = _store.getProxyType();
    final proxyAddress = _store.getProxyAddress();
    return Column(
      children: [
        CfTile(
          icon: Icons.link,
          title: '接口地址',
          subtitle: _store.getBaseUrl(),
          onTap: _editBaseUrl,
        ),
        CfTile(
          icon: Icons.key,
          title: 'API Key',
          subtitle: _store.getApiKey().isEmpty ? null : '••••••••',
          onTap: _editApiKey,
        ),
        CfTile(
          icon: Icons.memory,
          title: '模型名',
          subtitle: _store.getModel(),
          onTap: _editModel,
        ),
        CfTile(
          icon: Icons.vpn_lock_outlined,
          title: '代理类型',
          subtitle: _proxyTypes.firstWhere((item) => item.$1 == proxyType).$2,
          onTap: _editProxyType,
        ),
        if (proxyType != 0)
          CfTile(
            icon: Icons.dns_outlined,
            title: '代理地址',
            subtitle: proxyAddress.isEmpty ? '未填写' : proxyAddress,
            onTap: _editProxyAddress,
          ),
        CfTestButton(testing: _testing, onPressed: _testConnection),
      ],
    );
  }
}
