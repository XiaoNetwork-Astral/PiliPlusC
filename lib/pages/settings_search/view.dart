import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/pages/search/controller.dart' show DebounceStreamState;
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/settings_search/search_entries.dart';
import 'package:PiliPlus/pages/settings_search/search_jump.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState
    extends DebounceStreamState<SettingsSearchPage, String> {
  final _textEditingController = TextEditingController();
  final RxList<SettingsSearchEntry> _list = <SettingsSearchEntry>[].obs;
  late final _settings = buildSettingsSearchEntries();

  @override
  void onValueChanged(String value) {
    if (value.isEmpty) {
      _list.clear();
    } else {
      _list.value = _settings.where((item) => item.matches(value)).toList();
    }
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () {
              if (_textEditingController.text.isNotEmpty) {
                _textEditingController.clear();
                _list.clear();
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.clear),
          ),
          const SizedBox(width: 10),
        ],
        title: TextField(
          autofocus: true,
          controller: _textEditingController,
          textAlignVertical: TextAlignVertical.center,
          onChanged: ctr!.add,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '搜索',
            visualDensity: .standard,
            border: InputBorder.none,
          ),
        ),
      ),
      body: ViewInsetsSafeArea(
        child: CustomScrollView(
          slivers: [
            ViewSliverSafeArea(
              sliver: Obx(
                () => _list.isEmpty
                    ? const HttpError()
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildItem(context, _list[index]),
                          childCount: _list.length,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, SettingsSearchEntry item) {
    return ListTile(
      title: Text(item.title),
      onTap: () => _onTap(item),
    );
  }

  void _onTap(SettingsSearchEntry item) {
    final type = item.type;
    if (!MediaQuery.sizeOf(context).isPortrait && type != null) {
      Get.back(
        result: SettingsSearchJump(type: type, title: item.title),
      );
      return;
    }
    final page = item.page;
    if (page != null) {
      Get.to(page);
      return;
    }
    if (type != null) {
      Get.to(
        () => CommonSetting(
          settingType: type,
          highlightTitle: item.title,
        ),
      );
      return;
    }
    SmartDialog.showToast('没有可打开的页面');
  }
}
