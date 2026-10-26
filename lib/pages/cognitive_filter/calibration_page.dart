import 'dart:async';

import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_service.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

enum _Phase { idle, running, error, quiz, done }

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
  LlmErrorKind? _errorKind;
  String? _errorMessage;
  ({double before, double? after})? _result;

  @override
  void initState() {
    super.initState();
    unawaited(CalibrationService.instance.init());
  }

  Future<void> _start() async {
    if (_phase == _Phase.running) {
      return;
    }
    if (Pref.cfLlmApiKey.trim().isEmpty) {
      SmartDialog.showToast('请先填写整理接口的 API Key');
      return;
    }
    setState(() {
      _phase = _Phase.running;
      _batchDone = 0;
      _batchTotal = 0;
      _errorKind = null;
      _errorMessage = null;
      _questions = const <CalibrationQuestion>[];
      _answers =
          const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
      _index = 0;
      _result = null;
    });

    final outcome = await CalibrationService.instance.runRound(
      onProgress: (done, total) {
        if (!mounted || _phase != _Phase.running) {
          return;
        }
        setState(() {
          _batchDone = done;
          _batchTotal = total;
        });
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _questions = outcome.questions;
      _errorKind = outcome.abortedBy;
      _errorMessage = outcome.abortMessage;
      if (outcome.abortedBy != null || outcome.questions.isEmpty) {
        _phase = _Phase.error;
      } else {
        _phase = _Phase.quiz;
        _answers =
            const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
        _index = 0;
      }
    });
  }

  Future<void> _reset() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('确定重置校准数据？'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    await CalibrationService.instance.reset();
    if (!mounted) {
      return;
    }
    _backToStart();
  }

  /// 记录回答并显示下一题，答完最后一题时应用门槛调整
  void _answer(CalibrationAnswer answer) {
    if (_phase != _Phase.quiz || _index >= _questions.length) {
      return;
    }
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
      _questions = const <CalibrationQuestion>[];
      _answers =
          const <({CalibrationAnswer answer, CalibrationQuestion question})>[];
      _index = 0;
      _batchDone = 0;
      _batchTotal = 0;
      _errorKind = null;
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
        actions: _phase == _Phase.quiz
            ? <Widget>[
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
                ),
              ]
            : null,
      ),
      body: ViewSafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (_phase) {
      _Phase.idle => _buildIdle(context),
      _Phase.running => _buildRunning(context),
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

  Widget _buildIdle(BuildContext context) {
    return ListView(
      padding: _listPadding(context),
      children: [
        CfTile(
          icon: Icons.auto_awesome_outlined,
          title: '开始整理',
          onTap: _start,
        ),
        CfTile(
          icon: Icons.restart_alt,
          title: '重置校准数据',
          onTap: _reset,
        ),
      ],
    );
  }

  Widget _buildRunning(BuildContext context) {
    return ListView(
      padding: _listPadding(context),
      children: [
        CfTile(
          title: '正在整理',
          subtitle: _batchTotal > 0
              ? '第 $_batchDone 批，共 $_batchTotal 批'
              : null,
          trailing: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final kind = _errorKind;
    final message = _errorMessage;
    return ListView(
      padding: _listPadding(context),
      children: [
        CfTile(
          icon: kind == null ? Icons.inbox_outlined : Icons.error_outline,
          title: message == null || message.isEmpty ? '整理失败' : message,
        ),
        CfTile(
          icon: Icons.arrow_back,
          title: '返回',
          onTap: _backToStart,
        ),
      ],
    );
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
    return ListView(
      padding: _listPadding(context),
      children: [
        CfTile(
          icon: after != null ? Icons.tune : Icons.info_outline,
          title: after != null ? '已调整拦截门槛' : '回答太少，门槛没有改动',
          subtitle: after == null
              ? null
              : '${result!.before.toStringAsFixed(2)} 到 '
                    '${after.toStringAsFixed(2)}',
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
