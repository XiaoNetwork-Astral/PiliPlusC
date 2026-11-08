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
  String? _errorMessage;
  List<CategoryFit>? _result;

  /// 本页发起整理的代号，停止或重新开始后旧的结果不再处理
  int _startToken = 0;

  /// 本页发起的手动整理是否还没结束，离开页面时据此停掉
  bool _manualRoundRunning = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      CalibrationService.instance.init().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    // 本页发起的手动整理还没结束就离开，按停止处理，这一轮作废
    if (_manualRoundRunning) {
      _manualRoundRunning = false;
      CalibrationService.instance.stop();
    }
    super.dispose();
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
        _errorMessage = null;
        _questions = ready;
        _answers =
            const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
        _index = 0;
        _result = null;
      });
      return;
    }
    final token = ++_startToken;
    _manualRoundRunning = true;
    setState(() {
      _phase = _Phase.running;
      _errorMessage = null;
      _questions = const <CalibrationQuestion>[];
      _answers =
          const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
      _index = 0;
      _result = null;
    });

    final outcome = await CalibrationService.instance.prepareSession();
    if (token == _startToken) {
      _manualRoundRunning = false;
    }
    // 停止或离开后再回来的结果一律不处理
    if (!mounted || token != _startToken) return;
    if (outcome.cancelled) {
      // 这一轮已经作废，不是错误，安静回到起始状态
      _backToStart();
      return;
    }
    setState(() {
      if (outcome.questions.isNotEmpty) {
        _questions = outcome.questions;
        _phase = _Phase.quiz;
      } else if (outcome.abortedBy != null) {
        _errorMessage = outcome.abortMessage;
        _phase = _Phase.error;
      } else {
        _phase = _Phase.tooFew;
      }
    });
  }

  void _stop() {
    // 先让还在等结果的那次调用失效，再取消请求
    _startToken++;
    _manualRoundRunning = false;
    CalibrationService.instance.stop();
    // 不等这一轮收尾，立即回到起始状态，这一轮整理出的题也不要
    _backToStart();
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // 题库还不够答题时这一轮只是整理，不叫校准
              child: Text(ready ? '开始校准' : '开始整理'),
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
        final running = status.running;
        // 轮次结束后不再显示批次文字
        final total = running ? status.total : 0;
        final current = total == 0
            ? 0
            : (status.done + 1).clamp(1, total).toInt();
        return _centered([
          Text('正在整理', style: theme.textTheme.titleMedium),
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
                      // 只显示已经换行完成的文字，正在生成的那一行留在可见区外
                      child: _ThinkingStream(
                        text: text,
                        style:
                            theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                              height: 1.6,
                            ) ??
                            const TextStyle(height: 1.6),
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
              child: _SmoothProgress(
                running: running,
                done: status.done,
                total: status.total,
              ),
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
          OutlinedButton(onPressed: _stop, child: const Text('停止')),
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

/// 只显示已经换行结束的思考文字
///
/// 正在生成的那一行不显示，每完成一行把整段文字上移这一行的高度，
/// 用 300 毫秒的动画补上位移，用户看不到词一个个蹦出来
class _ThinkingStream extends StatefulWidget {
  const _ThinkingStream({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_ThinkingStream> createState() => _ThinkingStreamState();
}

class _ThinkingStreamState extends State<_ThinkingStream>
    with SingleTickerProviderStateMixin {
  static const Duration _scrollDuration = Duration(milliseconds: 300);

  late final AnimationController _controller;

  /// 当前文字整体向下偏移的量，动画到 0 时正好停在底部
  Animation<double> _offset = const AlwaysStoppedAnimation<double>(0);

  /// 正在显示的内容：截至最后一个换行之前的文字
  String _shown = '';

  /// 上一次布局时的可用宽度，用来量文字高度
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _scrollDuration);
    _shown = _completedOf(widget.text);
  }

  @override
  void didUpdateWidget(covariant _ThinkingStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _completedOf(widget.text);
    if (next == _shown) {
      return;
    }
    final delta = _heightOf(next) - _heightOf(_shown);
    _shown = next;
    if (delta <= 0) {
      // 思考文字被裁掉开头时内容会变短，直接显示新的内容
      _controller.stop();
      _offset = const AlwaysStoppedAnimation<double>(0);
      return;
    }
    // 上一次的位移还没走完时接着补，连续完成两行也不会跳
    _offset = Tween<double>(
      begin: _offset.value + delta,
      end: 0,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0);
  }

  /// 最后一个换行之前的文字，正在生成的那一行不在里面
  String _completedOf(String text) {
    final index = text.lastIndexOf('\n');
    if (index <= 0) {
      return '';
    }
    return text.substring(0, index);
  }

  /// 按当前宽度量出这段文字的高度，换行后的行数不同高度也不同
  double _heightOf(String text) {
    if (text.isEmpty || _width <= 0) {
      return 0;
    }
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: _width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _offset.value),
              child: child,
            ),
            child: OverflowBox(
              alignment: Alignment.bottomLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Text(_shown, style: widget.style),
            ),
          );
        },
      ),
    );
  }
}

/// 平滑前进的进度条
///
/// 每批真正完成才知道进度，直接按批跳会让人以为卡住，所以用这一轮
/// 已完成各批的平均用时估计当前批还要多久：先把这一批走到八成，
/// 超过预计用时后按很小的固定速度继续爬，全部完成前最多到 99%
class _SmoothProgress extends StatefulWidget {
  const _SmoothProgress({
    required this.running,
    required this.done,
    required this.total,
  });

  /// 当前是否真的有一轮整理在跑
  final bool running;

  final int done;
  final int total;

  @override
  State<_SmoothProgress> createState() => _SmoothProgressState();
}

class _SmoothProgressState extends State<_SmoothProgress>
    with SingleTickerProviderStateMixin {
  /// 一批都没完成时的预计用时，秒
  static const double _defaultBatchSeconds = 90;

  /// 在预计用时内走到这一批的八成
  static const double _batchReach = 0.8;

  /// 超过预计用时后每秒继续前进的进度
  static const double _creepPerSecond = 0.0015;

  /// 批完成后补上跳变的时间常数，秒
  static const double _catchUpTau = 0.25;

  /// 全部完成之前的进度上限
  static const double _cap = 0.99;

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  double _value = 0;

  /// 当前这一批开始的时刻，用 ticker 走过的时长表示
  Duration _batchStarted = Duration.zero;

  /// 这一轮已经完成的各批用时，秒
  final List<double> _batchSeconds = <double>[];

  /// 是否已经看到这一轮真正跑起来，没跑起来时不拿上一轮遗留的进度冒充
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _synced = widget.running;
    if (_synced) {
      _value = _startValue();
    }
    _ticker = createTicker(_onTick)..start();
  }

  double _startValue() {
    final total = widget.total;
    if (total <= 0) return 0;
    return (widget.done / total).clamp(0.0, _cap).toDouble();
  }

  @override
  void didUpdateWidget(covariant _SmoothProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 轮次已经结束，停在最后的位置等页面切走
    if (!widget.running) {
      return;
    }
    if (!oldWidget.running) {
      // 新的一轮跑起来了，从头开始
      _restart();
      _synced = true;
      _value = _startValue();
      return;
    }
    _synced = true;
    final total = widget.total;
    if (total <= 0) {
      // 总批数还没报出来
      if (oldWidget.total > 0) {
        _restart();
      }
      return;
    }
    // 总批数变了或完成数变少，说明换了一轮，从新的位置重新开始
    if (total != oldWidget.total || widget.done < oldWidget.done) {
      _restart();
      _value = _startValue();
      return;
    }
    if (widget.done == oldWidget.done) {
      return;
    }
    // 这一批实际用了多久，留给下一批估计
    final seconds = (_last - _batchStarted).inMicroseconds / 1e6;
    final batches = widget.done - oldWidget.done;
    if (seconds > 0 && batches > 0) {
      _batchSeconds.add(seconds / batches);
    }
    _batchStarted = _last;
  }

  void _restart() {
    _value = 0;
    _batchSeconds.clear();
    _batchStarted = _last;
  }

  /// 当前批的预计用时，取这一轮已完成各批的平均值
  double get _expectedSeconds {
    if (_batchSeconds.isEmpty) return _defaultBatchSeconds;
    var sum = 0.0;
    for (final seconds in _batchSeconds) {
      sum += seconds;
    }
    return math.max(sum / _batchSeconds.length, 0.1);
  }

  /// 此刻应该到的位置：预计用时内走到这一批的八成，之后按小速度继续爬
  double _targetAt(Duration elapsed) {
    final total = widget.total;
    if (widget.done >= total) return 1;
    final slice = 1 / total;
    final seconds = (elapsed - _batchStarted).inMicroseconds / 1e6;
    final expected = _expectedSeconds;
    final ramp = _batchReach * math.min(seconds / expected, 1.0);
    final overtime = math.max(seconds - expected, 0.0);
    final target =
        widget.done / total + slice * ramp + _creepPerSecond * overtime;
    return math.min(target, _cap);
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final total = widget.total;
    if (dt <= 0 || !_synced || !widget.running || total <= 0) return;
    final cap = widget.done >= total ? 1.0 : _cap;
    final target = math.min(_targetAt(elapsed), cap);
    var next = _value;
    if (next < target) {
      // 批完成时目标会往前跳一段，用很短的追赶时间平滑补上
      next += (target - next) * (1 - math.exp(-dt / _catchUpTau));
    }
    // 不管目标落在哪，都保留一点固定速度，进度条不会停住
    final floor = math.min(_value + _creepPerSecond * dt, cap);
    if (next < floor) next = floor;
    if (next > cap) next = cap;
    if (next != _value) setState(() => _value = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = _synced && widget.total > 0;
    return LinearProgressIndicator(
      minHeight: 4,
      value: known ? _value : null,
    );
  }
}
