import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart'
    show DynamicsDataModel, ItemModulesModel;
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;

List<SettingsModel> get dynSettings => [
  SplitModel(
    normalModel: const NormalModel.split(
      title: '检查未读动态',
      subtitle: '点击设置检查周期(min)',
      leading: Icon(Icons.notifications_none),
    ),
    switchModel: SwitchModel.split(
      defaultVal: true,
      setKey: SettingBoxKey.checkDynamic,
      onChanged: (value) => Get.find<MainController>().checkDynamic = value,
      onTap: _showDynDialog,
    ),
  ),
  SwitchModel(
    title: '显示动态警告/争议信息',
    leading: const Icon(Icons.warning_amber_rounded),
    setKey: SettingBoxKey.showDynDispute,
    defaultVal: false,
    onChanged: (val) => ItemModulesModel.showDynDispute = val,
  ),
  const SwitchModel(
    title: '发布/转发动态反诈',
    subtitle: '发布/转发动态后检查动态是否可见',
    leading: Icon(CustomIcons.shield_published),
    setKey: SettingBoxKey.enableCreateDynAntifraud,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '动态/专栏详情页展示底部操作栏',
    leading: Icon(Icons.more_horiz),
    setKey: SettingBoxKey.showDynActionBar,
    defaultVal: true,
  ),
  PopupModel(
    title: '动态展示',
    leading: const Icon(Icons.dynamic_feed_rounded),
    value: () => Pref.defaultDynamicType,
    items: DynamicsTabType.values.take(4),
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.defaultDynamicType, value.index)
        .whenComplete(setState),
  ),
  SwitchModel(
    title: '显示动态互动内容',
    subtitle: '开启后则在动态卡片底部显示互动内容（如关注的人点赞、热评等）',
    leading: const Icon(Icons.quickreply_outlined),
    setKey: SettingBoxKey.showDynInteraction,
    defaultVal: true,
    onChanged: (val) => ItemModulesModel.showDynInteraction = val,
  ),
];

/// 动态屏蔽相关的设置项，放在认知滤网里，不再出现在动态设置页
List<SettingsModel> get dynBlockSettings => [
  SwitchModel(
    title: '屏蔽带货动态',
    leading: const Icon(CustomIcons.shopping_bag_not_interested),
    setKey: SettingBoxKey.antiGoodsDyn,
    defaultVal: false,
    onChanged: (value) => DynamicsDataModel.antiGoodsDyn = value,
  ),
];

void _showDynDialog(BuildContext context) {
  String dynamicPeriod = Pref.dynamicPeriod.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('检查周期'),
      content: TextFormField(
        autofocus: true,
        initialValue: dynamicPeriod,
        keyboardType: TextInputType.number,
        onChanged: (value) => dynamicPeriod = value,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(suffixText: 'min'),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            try {
              final val = int.parse(dynamicPeriod);
              Get.back();
              GStorage.setting.put(SettingBoxKey.dynamicPeriod, val);
              Get.find<MainController>().dynamicPeriod = val * 60 * 1000;
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
