import 'dart:async';
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/calibration_settings_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/rule_list_page.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_core.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/guard_rules_source.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

enum _Phase { idle, running, tooFew, error, quiz, done }

enum _MenuAction { settings, guard, reset }

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
  bool _stopping = false;
  String? _errorMessage;
  List<CategoryFit>? _result;

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

  int get _bankSize => CalibrationService.instance.bankSize;

  Future<void> _start() async {
    if (_phase == _Phase.running) return;
    // 题库够答就直接开始答题，不经过整理页
    final ready = CalibrationService.instance.bankQuestions();
    if (ready.length >= calibrationMinQuestions) {
      setState(() {
        _phase = _Phase.quiz;
        _stopping = false;
        _errorMessage = null;
        _questions = ready;
        _answers =
            const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
        _index = 0;
        _result = null;
      });
      return;
    }
    setState(() {
      _phase = _Phase.running;
      _stopping = false;
      _errorMessage = null;
      _questions = const <CalibrationQuestion>[];
      _answers =
          const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
      _index = 0;
      _result = null;
    });

    final outcome = await CalibrationService.instance.prepareSession();
    if (!mounted) return;
    setState(() {
      if (outcome.questions.isNotEmpty) {
        // 用户停止时，已经整理出的题照常拿来答
        _questions = outcome.questions;
        _phase = _Phase.quiz;
      } else if (_stopping) {
        _phase = _Phase.idle;
      } else if (outcome.abortedBy != null) {
        _errorMessage = outcome.abortMessage;
        _phase = _Phase.error;
      } else {
        _phase = _Phase.tooFew;
      }
    });
  }

  void _stop() {
    CalibrationService.instance.stop();
    setState(() => _stopping = true);
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
      case _MenuAction.settings:
        Get.to(() => const CalibrationSettingsPage());
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
    CalibrationService.instance.finishSession(_questions);
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
      _stopping = false;
      _questions = const <CalibrationQuestion>[];
      _answers =
          const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
      _index = 0;
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
                PopupMenuItem(value: _MenuAction.settings, child: Text('设置')),
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

  Widget _countCard(ThemeData theme, String label, int count, String unit) {
    return Container(
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
            label,
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
              Text(unit, style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    // 数量随后台整理实时变化
    return ValueListenableBuilder<int>(
      valueListenable: CalibrationService.instance.revision,
      builder: (context, _, _) {
        final count = _poolSize;
        final bank = _bankSize;
        // 题库里已有够答的题时，不需要密钥也不需要池里有内容
        final ready = bank >= calibrationMinQuestions;
        final String? blocker = ready
            ? null
            : !_hasKey
            ? '请先在 AI 提供商里填写整理接口的 API Key'
            : count == 0
            ? '还没有可整理的内容，正常使用一阵再来'
            : null;
        return _centered([
          _countCard(theme, '已攒下可整理的内容', count, '条'),
          const SizedBox(height: 12),
          _countCard(theme, '已整理好的题', bank, '道'),
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
      },
    );
  }

  Widget _buildRunning(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ValueListenableBuilder<OrganizeStatus>(
      valueListenable: CalibrationService.instance.status,
      builder: (context, status, _) {
        final total = status.total;
        final current = total == 0
            ? 0
            : (status.done + 1).clamp(1, total).toInt();
        return _centered([
          Text(
            _stopping ? '正在停止' : '正在整理',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 260,
            height: 132,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                    stops: [0.0, 0.35],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ValueListenableBuilder<String>(
                    valueListenable: CalibrationService.instance.thinking,
                    builder: (context, text, _) => Padding(
                      padding: const EdgeInsets.all(12),
                      // 文字贴底排版、顶部溢出，每一行都是同样地从下往上移出
                      child: OverflowBox(
                        alignment: Alignment.bottomLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Text(
                          text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: _SmoothProgress(done: status.done, total: total),
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            Text(
              '第 $current 批，共 $total 批',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _stopping ? null : _stop,
            child: const Text('停止'),
          ),
        ]);
      },
    );
  }

  Widget _buildTooFew(BuildContext context) {
    final theme = Theme.of(context);
    return _centered([
      Icon(Icons.inbox_outlined, size: 40, color: theme.colorScheme.outline),
      const SizedBox(height: 12),
      Text('整理出的题不到 10 道，攒一些再试', style: theme.textTheme.titleMedium),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'AI 判定类别：$category',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  representative.text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
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
            ],
          ),
        ),
      ),
    );
  }

  /// 完成页顶部的圆角卡片，成功用绿色、失败用红色，左右留边不占满整行
  Widget _doneCard(
    BuildContext context, {
    required bool success,
    required String title,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final Color background;
    final Color foreground;
    if (success) {
      background = dark ? const Color(0xFF1F3D2B) : const Color(0xFFD7F0DE);
      foreground = dark ? const Color(0xFFB9E6C5) : const Color(0xFF14532D);
    } else {
      background = dark ? const Color(0xFF4A1F1F) : const Color(0xFFFBDADA);
      foreground = dark ? const Color(0xFFF5C2C2) : const Color(0xFF7F1D1D);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              success ? Icons.check_circle_outline : Icons.error_outline,
              color: foreground,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final fits = _result;
    if (fits == null || fits.isEmpty) {
      return ListView(
        padding: _listPadding(context),
        children: [
          _doneCard(context, success: false, title: '回答太少，门槛没有改动'),
        ],
      );
    }
    return ListView(
      padding: _listPadding(context),
      children: [
        _doneCard(
          context,
          success: true,
          title: '已完成校准',
          subtitle: '现已使用新的数值进行拦截',
        ),
        for (final fit in fits)
          CfTile(
            icon: Icons.tune,
            title: fit.name,
            subtitle: fit.after.toStringAsFixed(2),
          ),
      ],
    );
  }
}

/// 平滑前进的进度条
///
/// 每批真正完成才知道进度，直接按批跳会让人焦急，所以在两次完成之间
/// 往"这一批做完时的位置"慢慢靠近，只前进不回退，没全部完成前不到头
class _SmoothProgress extends StatefulWidget {
  const _SmoothProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  State<_SmoothProgress> createState() => _SmoothProgressState();
}

class _SmoothProgressState extends State<_SmoothProgress>
    with SingleTickerProviderStateMixin {
  /// 向目标靠近的时间常数，秒，越大越慢
  static const double _tau = 8;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _value = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  /// 这一批做完时的位置，留一点余量，最后一批也到不了 100%
  double get _cap {
    final total = widget.total;
    if (total <= 0) return 0;
    final cap = (widget.done + 0.92) / total;
    return cap.clamp(0.0, 0.98).toDouble();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    // 已完成的批数是下限，只前进不回退
    final floor = widget.total <= 0
        ? 0.0
        : (widget.done / widget.total).clamp(0.0, 0.98).toDouble();
    var next = _value < floor ? floor : _value;
    final cap = _cap;
    if (next < cap) {
      next += (cap - next) * (1 - math.exp(-dt / _tau));
    }
    if (next != _value) setState(() => _value = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      minHeight: 4,
      value: widget.total <= 0 ? null : _value,
    );
  }
}
