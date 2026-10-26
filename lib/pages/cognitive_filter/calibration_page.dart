import 'dart:async';

import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/config.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_list_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_core.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/guard_rules_source.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

enum _Phase { idle, running, tooFew, error, quiz, done }

enum _MenuAction { guard, reset }

/// 校准向导
///
/// 从收集池里拿出高分内容，交给整理接口归类，用户一次回答一类，
/// 答完据此微调屏蔽门槛
class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key});

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  _Phase _phase = _Phase.idle;

  List<CalibrationQuestion> _questions = const <CalibrationQuestion>[];
  List<({CalibrationAnswer answer, CalibrationQuestion question})> _answers =
      const <({CalibrationAnswer answer, CalibrationQuestion question})>[];

  int _index = 0;
  int _batchDone = 0;
  int _batchTotal = 0;
  bool _cancelled = false;
  String? _errorMessage;
  ({double before, double? after})? _result;

  @override
  void initState() {
    super.initState();
    unawaited(
      CalibrationService.instance.init().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  bool get _hasKey => Pref.cfLlmApiKey.trim().isNotEmpty;

  int get _poolSize => CalibrationService.instance.poolSize;

  Future<void> _start() async {
    if (_phase == _Phase.running) return;
    setState(() {
      _phase = _Phase.running;
      _cancelled = false;
      _batchDone = 0;
      _batchTotal = 0;
      _errorMessage = null;
      _questions = const <CalibrationQuestion>[];
      _answers =
          const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
      _index = 0;
      _result = null;
    });

    final outcome = await CalibrationService.instance.runRound(
      onProgress: (done, total) {
        if (!mounted || _phase != _Phase.running) return;
        setState(() {
          _batchDone = done;
          _batchTotal = total;
        });
      },
      shouldCancel: () => _cancelled,
    );
    if (!mounted) return;
    setState(() {
      if (_cancelled) {
        _phase = _Phase.idle;
      } else if (outcome.abortedBy != null) {
        _errorMessage = outcome.abortMessage;
        _phase = _Phase.error;
      } else if (outcome.questions.isEmpty) {
        _phase = _Phase.tooFew;
      } else {
        _questions = outcome.questions;
        _phase = _Phase.quiz;
      }
    });
  }

  void _stop() {
    setState(() => _cancelled = true);
  }

  Future<void> _reset() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定重置校准数据？'),
    );
    if (!confirmed || !mounted) return;
    await CalibrationService.instance.reset();
    if (!mounted) return;
    _backToStart();
  }

  void _onMenu(_MenuAction action) {
    switch (action) {
      case _MenuAction.guard:
        Get.to(
          () => RuleListPage(
            source: GuardRulesSource.instance,
            title: '不外传规则',
            allowedScopes: aiWhitelistScopes,
          ),
        );
      case _MenuAction.reset:
        _reset();
    }
  }

  /// 记录回答并显示下一题，答完最后一题时应用门槛调整
  void _answer(CalibrationAnswer answer) {
    if (_phase != _Phase.quiz || _index >= _questions.length) return;
    final next =
        <({CalibrationAnswer answer, CalibrationQuestion question})>[
          ..._answers,
          (answer: answer, question: _questions[_index]),
        ];
    if (_index + 1 < _questions.length) {
      setState(() {
        _answers = next;
        _index++;
      });
      return;
    }
    final result = CalibrationService.instance.apply(next);
    setState(() {
      _answers = next;
      _result = result;
      _phase = _Phase.done;
    });
  }

  /// 回到起始状态，已答的题不保存
  void _backToStart() {
    setState(() {
      _phase = _Phase.idle;
      _cancelled = false;
      _questions = const <CalibrationQuestion>[];
      _answers =
          const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
      _index = 0;
      _batchDone = 0;
      _batchTotal = 0;
      _errorMessage = null;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('校准向导'),
        actions: <Widget>[
          if (_phase == _Phase.quiz)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_index + 1} / ${_questions.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            )
          else if (_phase == _Phase.idle)
            PopupMenuButton<_MenuAction>(
              onSelected: _onMenu,
              itemBuilder: (context) => const [
                PopupMenuItem(value: _MenuAction.guard, child: Text('不外传规则')),
                PopupMenuItem(
                  value: _MenuAction.reset,
                  child: Text('重置校准数据'),
                ),
              ],
            ),
        ],
      ),
      body: ViewSafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (_phase) {
      _Phase.idle => _buildIdle(context),
      _Phase.running => _buildRunning(context),
      _Phase.tooFew => _buildTooFew(context),
      _Phase.error => _buildError(context),
      _Phase.quiz => _buildQuiz(context),
      _Phase.done => _buildDone(context),
    };
  }

  EdgeInsets _listPadding(BuildContext context) {
    return EdgeInsets.only(
      bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
    );
  }

  /// 页面正中的一列：卡片或图标、说明文字、按钮
  Widget _centered(List<Widget> children) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    final count = _poolSize;
    final String? blocker = !_hasKey
        ? '请先在 AI 提供商里填写整理接口的 API Key'
        : count == 0
        ? '还没有可整理的内容，正常使用一阵再来'
        : null;
    return _centered([
      Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已攒下可整理的内容',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$count', style: theme.textTheme.headlineMedium),
                const SizedBox(width: 4),
                Text('条', style: theme.textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      FilledButton.tonal(
        onPressed: blocker == null ? _start : null,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('开始校准'),
        ),
      ),
      if (blocker != null) ...[
        const SizedBox(height: 12),
        Text(
          blocker,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    ]);
  }

  Widget _buildRunning(BuildContext context) {
    final theme = Theme.of(context);
    return _centered([
      const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
      const SizedBox(height: 16),
      Text(_cancelled ? '正在停止' : '正在整理', style: theme.textTheme.titleMedium),
      if (_batchTotal > 0) ...[
        const SizedBox(height: 6),
        Text(
          '第 $_batchDone 批，共 $_batchTotal 批',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: _cancelled ? null : _stop,
        child: const Text('停止'),
      ),
    ]);
  }

  Widget _buildTooFew(BuildContext context) {
    final theme = Theme.of(context);
    return _centered([
      Icon(Icons.inbox_outlined, size: 40, color: theme.colorScheme.outline),
      const SizedBox(height: 12),
      Text('这轮整理出的题不多，攒一些再试', style: theme.textTheme.titleMedium),
      const SizedBox(height: 24),
      OutlinedButton(onPressed: _backToStart, child: const Text('返回')),
    ]);
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = (_errorMessage ?? '').trim();
    return _centered([
      Icon(Icons.error_outline, size: 40, color: scheme.error),
      const SizedBox(height: 12),
      Text('整理失败', style: theme.textTheme.titleMedium),
      if (message.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
              color: scheme.onErrorContainer,
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(onPressed: _backToStart, child: const Text('返回')),
          const SizedBox(width: 12),
          FilledButton.tonal(onPressed: _start, child: const Text('重试')),
        ],
      ),
    ]);
  }

  Widget _buildQuiz(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final representative = _questions[_index].representative;
    final category = representative.category.isEmpty
        ? '未知'
        : representative.category;
    return ListView(
      padding: _listPadding(context),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            representative.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'AI 判定类别：$category',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.outline,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answer(CalibrationAnswer.block),
                  child: const Text('该拦'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answer(CalibrationAnswer.skip),
                  child: const Text('拿不准'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answer(CalibrationAnswer.keep),
                  child: const Text('不该拦'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final result = _result;
    final after = result?.after;
    if (result == null || after == null) {
      return ListView(
        padding: _listPadding(context),
        children: [
          const CfTile(
            icon: Icons.info_outline,
            title: '回答太少，门槛没有改动',
          ),
          CfTile(
            icon: Icons.arrow_back,
            title: '返回',
            onTap: _backToStart,
          ),
        ],
      );
    }
    final before = result.before;
    final changed = (after - before).abs() >= 0.005;
    final categories = CognitiveFilterConfig.effectiveCategories
        .where((category) => category.builtin && category.enabled)
        .toList();
    return ListView(
      padding: _listPadding(context),
      children: [
        const CfTile(
          icon: Icons.check_circle_outline,
          title: '已完成校准',
          subtitle: '现已使用新的数值进行拦截',
        ),
        if (changed)
          for (final category in categories)
            CfTile(
              icon: Icons.tune,
              title: category.name,
              subtitle:
                  '${before.toStringAsFixed(2)} → ${after.toStringAsFixed(2)}',
            )
        else
          const CfTile(
            icon: Icons.equalizer,
            title: '各类别的门槛没有变化',
          ),
        CfTile(
          icon: Icons.arrow_back,
          title: '返回',
          onTap: _backToStart,
        ),
      ],
    );
  }
}
