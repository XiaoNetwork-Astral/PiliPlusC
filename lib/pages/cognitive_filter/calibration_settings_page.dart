import 'package:PiliPlus/common/widgets/dialog/text_input_dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_service.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 校准向导自己的设置：后台自动整理与题库上限
///
/// 整理的重试与费用上限用 AI 提供商页里整理接口的设置
class CalibrationSettingsPage extends StatefulWidget {
  const CalibrationSettingsPage({super.key});

  @override
  State<CalibrationSettingsPage> createState() =>
      _CalibrationSettingsPageState();
}

class _CalibrationSettingsPageState extends State<CalibrationSettingsPage> {
  late bool _auto = Pref.cfCalibAuto;
  late int _cap = Pref.cfCalibBankCap;

  void _setAuto(bool value) {
    Pref.cfCalibAuto = value;
    setState(() => _auto = value);
    CalibrationService.instance.onSettingsChanged();
  }

  Future<void> _editCap() async {
    final result = await showTextInputDialog(
      context: context,
      title: '整理到多少道题后暂停',
      initialValue: _cap.toString(),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      suffixText: '道',
      validator: (value) {
        final count = int.tryParse(value);
        if (count == null || count < 10 || count > 500) {
          return '请输入 10 到 500 之间的数';
        }
        return null;
      },
    );
    if (result == null) return;
    final count = int.parse(result);
    Pref.cfCalibBankCap = count;
    setState(() => _cap = count);
    CalibrationService.instance.onSettingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('校准向导设置')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            CfSwitchTile(
              icon: Icons.auto_mode_outlined,
              title: '后台自动整理',
              value: _auto,
              onChanged: _setAuto,
            ),
            CfTile(
              icon: Icons.quiz_outlined,
              title: '整理到多少道题后暂停',
              trailing: Text(
                '$_cap',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              onTap: _editCap,
            ),
          ],
        ),
      ),
    );
  }
}
