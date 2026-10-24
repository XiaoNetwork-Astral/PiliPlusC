import 'dart:io' show Directory, File, Platform;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart'
    show RefreshIndicator, displacement, refreshDragExtent;
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart'
    show deviceTouchSlop, touchSlopH;
import 'package:PiliPlus/common/widgets/image_grid/image_grid_view.dart'
    show ImageGridView, ImageModel;
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/filtering_text.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

List<SettingsModel> get extraSettings => [
  if (PlatformUtils.isDesktop)
    SwitchModel(
      title: '退出时最小化',
      leading: const Icon(Icons.exit_to_app),
      setKey: SettingBoxKey.minimizeOnExit,
      defaultVal: true,
      onChanged: (value) => WindowController.instance.minimizeOnExit = value,
    ),
  if (PlatformUtils.isDesktop || Platform.isAndroid)
    NormalModel(
      title: '缓存路径',
      getSubtitle: () => Platform.isAndroid
          ? _androidVideoCacheCodename(downloadPath)
          : downloadPath,
      leading: const Icon(Icons.storage),
      onTap: _showDownPathDialog,
    ),
  if (Platform.isAndroid)
    SwitchModel(
      title: '允许三方APP访问私有存储',
      subtitle: '允许三方APP（例如MT管理器）通过访问外部存储的方式访问私有存储下的文件',
      leading: const Icon(Icons.storage),
      setKey: SettingBoxKey.enableDocProvider,
      defaultVal: Pref.enableDocProvider,
      onChanged: AndroidHelper.updateDocProvider,
    ),
  SplitModel(
    normalModel: const NormalModel.split(
      title: '空降助手',
      subtitle: '点击配置',
      leading: Icon(CustomIcons.shield_play_arrow),
    ),
    switchModel: SwitchModel.split(
      defaultVal: false,
      setKey: SettingBoxKey.enableSponsorBlock,
      onTap: (context) => Get.toNamed('/sponsorBlock'),
    ),
  ),
  PopupModel<SkipType>(
    title: '番剧片头/片尾跳过类型',
    leading: const Icon(MdiIcons.debugStepOver),
    value: () => Pref.pgcSkipType,
    items: SkipType.values,
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.pgcSkipType, value.index)
        .whenComplete(setState),
  ),
  const SwitchModel(
    title: '禁用 SSL 证书验证',
    subtitle: '谨慎开启，禁用容易受到中间人攻击',
    leading: Icon(Icons.security),
    needReboot: true,
    setKey: SettingBoxKey.badCertificateCallback,
  ),
  if (Platform.isAndroid)
    getSaveImgPathModel(
      title: '图片 保存路径',
      imgPathKey: SettingBoxKey.imageSavePath,
      suffix: 'bili',
    ),
  const SwitchModel(
    title: '使用外部浏览器打开链接',
    leading: Icon(Icons.open_in_browser),
    setKey: SettingBoxKey.openInBrowser,
    defaultVal: false,
  ),
  NormalModel(
    title: '横向滑动阈值',
    getSubtitle: () => '当前:「${Pref.touchSlopH}」，系统默认值: $deviceTouchSlop',
    onTap: _showTouchSlopDialog,
    leading: const Icon(Icons.pan_tool_alt_outlined),
  ),
  NormalModel(
    title: '刷新指示器高度',
    leading: const Icon(Icons.height),
    getSubtitle: () =>
        '当前指示器高度: ${Pref.refreshDisplacement}, 刷新滑动距离: $refreshDragExtent',
    onTap: _showRefreshDialog,
  ),
  const SwitchModel(
    title: '显示热门推荐',
    subtitle: '热门页面显示每周必看等推荐内容入口',
    leading: Icon(Icons.local_fire_department_outlined),
    setKey: SettingBoxKey.showHotRcmd,
    defaultVal: false,
    needReboot: true,
  ),
  const SwitchModel(
    title: '搜索建议',
    leading: Icon(Icons.search),
    setKey: SettingBoxKey.searchSuggestion,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '记录搜索历史',
    leading: Icon(Icons.history),
    setKey: SettingBoxKey.recordSearchHistory,
    defaultVal: true,
  ),
  SwitchModel(
    title: '预览 Live Photo',
    subtitle: '开启则以视频形式预览 Live Photo，否则预览静态图片',
    leading: const Icon(Icons.image_outlined),
    setKey: SettingBoxKey.enableLivePhoto,
    defaultVal: true,
    onChanged: (value) => ImageModel.enableLivePhoto = value,
  ),
  SwitchModel(
    title: '侧滑关闭二级页面',
    leading: const Icon(CustomIcons.touch_app_rotate_270),
    setKey: SettingBoxKey.slideDismissReplyPage,
    defaultVal: Platform.isIOS,
    onChanged: (value) => CommonSlideMixin.slideDismissReplyPage = value,
  ),
  const SwitchModel(
    title: '展示追番时间表',
    leading: Icon(MdiIcons.chartTimelineVariantShimmer),
    setKey: SettingBoxKey.showPgcTimeline,
    defaultVal: true,
    needReboot: true,
  ),
  SwitchModel(
    title: '静默下载图片',
    subtitle: '不显示下载 Loading 弹窗',
    leading: const Icon(Icons.download_for_offline_outlined),
    setKey: SettingBoxKey.silentDownImg,
    defaultVal: false,
    onChanged: (value) => ImageUtils.silentDownImg = value,
  ),
  SwitchModel(
    title: '长按/右键显示图片菜单',
    leading: const Icon(Icons.menu),
    setKey: SettingBoxKey.enableImgMenu,
    defaultVal: false,
    onChanged: (value) => ImageGridView.enableImgMenu = value,
  ),
  SwitchModel(
    setKey: SettingBoxKey.feedBackEnable,
    onChanged: (value) {
      enableFeedback = value;
      feedBack();
    },
    leading: const Icon(Icons.vibration_outlined),
    title: '震动反馈',
    subtitle: '请确定手机设置中已开启震动反馈',
  ),
  const SwitchModel(
    title: '大家都在搜',
    subtitle: '是否展示「大家都在搜」',
    leading: Icon(Icons.data_thresholding_outlined),
    setKey: SettingBoxKey.enableHotKey,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '搜索发现',
    subtitle: '是否展示「搜索发现」',
    leading: Icon(Icons.search_outlined),
    setKey: SettingBoxKey.enableSearchRcmd,
    defaultVal: true,
  ),
  SwitchModel(
    title: '搜索默认词',
    subtitle: '是否展示搜索框默认词',
    leading: const Icon(Icons.whatshot_outlined),
    setKey: SettingBoxKey.enableSearchWord,
    defaultVal: false,
    onChanged: (val) {
      try {
        final controller = Get.find<HomeController>()..enableSearchWord = val;
        if (val) {
          controller.querySearchDefault();
        } else {
          controller.defaultSearch.value = '';
        }
      } catch (_) {}
    },
  ),
  const SwitchModel(
    title: '显示剪贴板搜索',
    subtitle: '首页搜索框旁显示剪贴板粘贴按钮',
    leading: Icon(Icons.paste),
    setKey: SettingBoxKey.showClipboardSearch,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '剪贴板无痕搜索',
    subtitle: '剪贴板搜索时不记录搜索历史',
    leading: Icon(Icons.visibility_off_outlined),
    setKey: SettingBoxKey.clipboardSearchIncognito,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '快速收藏',
    subtitle: '点击设置默认收藏夹\n点按收藏至默认，长按选择文件夹',
    leading: Icon(Icons.bookmark_add_outlined),
    setKey: SettingBoxKey.enableQuickFav,
    onTap: _showFavDialog,
    defaultVal: false,
  ),
  SwitchModel(
    title: '快速分享给指定用户',
    subtitle: '长按分享触发，点击指定用户',
    leading: const Icon(FontAwesomeIcons.shareFromSquare),
    setKey: SettingBoxKey.enableQuickShare,
    defaultVal: false,
    onChanged: (value) async {
      if (value && Accounts.main.isLogin) {
        final TextEditingController controller = TextEditingController();
        final quickShareId = Pref.quickShareId;
        if (quickShareId != null && quickShareId != 1004428694) {
          controller.text = quickShareId.toString();
        }
        final result = await showDialog<bool>(
          context: Get.context!,
          builder: (context) => AlertDialog(
            title: const Text('默认分享对象的mid'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '空白默认为开发者mid',
              ),
              keyboardType: TextInputType.number,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Get.back(result: false);
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Get.back(result: true);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (result == true) {
          final inputText = controller.text.trim();
          if (inputText.isEmpty) {
            await GStorage.setting.put(SettingBoxKey.quickShareId, 1004428694);
            SmartDialog.showToast('设置成功');
          } else {
            final mid = int.tryParse(inputText);
            if (mid != null) {
              await GStorage.setting.put(SettingBoxKey.quickShareId, mid);
              SmartDialog.showToast('设置成功');
            } else {
              SmartDialog.showToast('请输入正确mid');
              await GStorage.setting.put(SettingBoxKey.enableQuickShare, false);
            }
          }
        } else {
          await GStorage.setting.put(SettingBoxKey.enableQuickShare, false);
        }
      }
    },
  ),
  const SwitchModel(
    title: '启用AI总结',
    subtitle: '视频详情页开启AI总结',
    leading: Icon(Icons.engineering_outlined),
    setKey: SettingBoxKey.enableAi,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '消息页禁用"收到的赞"功能',
    subtitle: '禁止打开入口，降低网络社交依赖',
    leading: Icon(Icons.beach_access_outlined),
    setKey: SettingBoxKey.disableLikeMsg,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '长按展示视频卡片替换为加入稍后再看',
    subtitle: '开启后不再展示长按弹窗',
    leading: Icon(Icons.watch_later_outlined),
    setKey: SettingBoxKey.defaultAddWatchLater,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '"我的"页默认打开稍后再看',
    leading: Icon(Icons.watch_later_outlined),
    setKey: SettingBoxKey.defaultShowWatchLater,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '启用HTTP/2',
    leading: Icon(Icons.swap_horizontal_circle_outlined),
    setKey: SettingBoxKey.enableHttp2,
    defaultVal: false,
    needReboot: true,
  ),
  const NormalModel(
    title: '连接重试次数',
    subtitle: '为0时禁用',
    leading: Icon(Icons.repeat),
    onTap: _showReplyCountDialog,
  ),
  const NormalModel(
    title: '连接重试间隔',
    subtitle: '实际间隔 = 间隔 * 第x次重试',
    leading: Icon(Icons.more_time_outlined),
    onTap: _showReplyDelayDialog,
  ),
  const SplitModel(
    normalModel: NormalModel.split(
      title: '设置代理',
      subtitle: '设置代理 host:port',
      leading: Icon(Icons.airplane_ticket_outlined),
    ),
    switchModel: SwitchModel.split(
      defaultVal: false,
      setKey: SettingBoxKey.enableSystemProxy,
      onTap: _showProxyDialog,
    ),
  ),
  NormalModel(
    title: '最大缓存大小',
    getSubtitle: () => '当前最大缓存大小: 「${Pref.maxCacheSize.formatSize}」',
    leading: const Icon(Icons.delete_outlined),
    onTap: _showCacheDialog,
  ),
  SwitchModel(
    title: '检查更新',
    subtitle: '每次启动时检查是否需要更新',
    leading: const Icon(Icons.system_update_alt),
    setKey: SettingBoxKey.autoUpdate,
    defaultVal: true,
    onChanged: (val) {
      if (val) {
        Update.checkUpdate(false);
      }
    },
  ),
  NormalModel(
    title: '设置港澳台代理',
    getSubtitle: () {
      final url = Pref.apiHKUrl;
      return '当前港澳台代理: 「${url.isEmpty ? '不代理' : url}」';
    },
    leading: const Icon(Icons.sailing_rounded),
    onTap: (context, setState) {
      showDialog(
        context: context,
        builder: (context) {
          String valueStr = '';
          return AlertDialog(
            title: const Text('港澳台代理链接'),
            content: TextField(
              autofocus: true,
              onChanged: (value) => valueStr = value,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: '请输入URL如:https://app.bilibili.com',
              ),
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
                onPressed: () async {
                  if (valueStr.isEmpty) {
                    SmartDialog.showToast('代理链接不能为空');
                    return;
                  }
                  if (!valueStr.toLowerCase().startsWith('http')) {
                    SmartDialog.showToast('代理链接格式错误');
                    return;
                  }
                  if (valueStr.endsWith('/')) {
                    SmartDialog.showToast('末尾不能有/');
                    return;
                  }

                  Get.back();
                  await GStorage.setting.put(SettingBoxKey.apiHKUrl, valueStr);
                  setState();
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  ),
];

void _showDownPathDialog(BuildContext context, VoidCallback setState) {
  if (Platform.isAndroid) {
    _showAndroidDownPathDialog(context, setState);
    return;
  }

  showDialog(
    context: context,
    builder: (context) => SimpleDialog(
      clipBehavior: Clip.hardEdge,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        DialogOption(
          onPressed: () {
            Get.back();
            PathUtils.openDir(downloadPath);
          },
          child: const Text('打开'),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            Utils.copyText(downloadPath);
          },
          child: const Text('复制', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () async {
            Get.back();
            final defPath = defDownloadPath;
            if (downloadPath == defPath) return;
            await _applyDownloadPath(
              defPath,
              setState: setState,
              persist: false,
            );
          },
          child: const Text('重置', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () async {
            Get.back();
            final selectedPath = await FilePicker.getDirectoryPath(
              initialDirectory: Directory(downloadPath).existsSync()
                  ? downloadPath
                  : null,
            );
            if (selectedPath == null || selectedPath == downloadPath) return;
            await _applyDownloadPath(
              selectedPath,
              setState: setState,
              persist: true,
            );
          },
          child: const Text('设置新路径', style: TextStyle(fontSize: 14)),
        ),
      ],
    ),
  );
}

Future<void> _showAndroidDownPathDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  SmartDialog.showLoading();
  final values = await _getAndroidVideoCachePathOptions();
  SmartDialog.dismiss();
  if (!context.mounted) return;

  final selected = await showDialog<String>(
    context: context,
    builder: (context) => SelectDialog<String>(
      value: downloadPath,
      values: values,
      title: '选择缓存路径存储位置',
      subtitleBuilder: (_, index) => _VideoCachePathSubtitle(
        dirPath: values[index].$1,
      ),
    ),
  );
  if (selected == null || selected == downloadPath) return;
  await _applyDownloadPath(selected, setState: setState, persist: true);
}

class _VideoCachePathSubtitle extends StatefulWidget {
  final String dirPath;

  const _VideoCachePathSubtitle({required this.dirPath});

  @override
  State<_VideoCachePathSubtitle> createState() =>
      _VideoCachePathSubtitleState();
}

class _VideoCachePathSubtitleState extends State<_VideoCachePathSubtitle> {
  late final Future<int> _futureCount = _countVideoCacheEntries(widget.dirPath);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _futureCount,
      builder: (context, snapshot) {
        final countText = snapshot.connectionState == ConnectionState.done
            ? '视频数量：${snapshot.data ?? 0}'
            : '视频数量：计算中...';
        return Text(
          '${widget.dirPath}\n$countText',
          style: const TextStyle(fontSize: 12),
        );
      },
    );
  }
}

Future<int> _countVideoCacheEntries(String downloadDirPath) async {
  try {
    final root = Directory(downloadDirPath);
    if (!root.existsSync()) return 0;

    var count = 0;
    await for (final pageDir in root.list(followLinks: false)) {
      if (pageDir is! Directory) continue;
      await for (final entryDir in pageDir.list(followLinks: false)) {
        if (entryDir is! Directory) continue;
        final entryFile = File(
          path.join(entryDir.path, biliDownloadEntryFileName),
        );
        if (entryFile.existsSync()) {
          count++;
        }
      }
    }
    return count;
  } catch (_) {
    return 0;
  }
}

Future<String> _getAndroidDefaultVideoCachePath() async {
  final externalStorageDirPath = (await getExternalStorageDirectory())?.path;
  return externalStorageDirPath != null
      ? path.join(externalStorageDirPath, PathUtils.downloadDir)
      : defDownloadPath;
}

Future<List<(String, String)>> _getAndroidVideoCachePathOptions() async {
  final results = <(String, String)>[];
  final seen = <String>{};

  void add(String downloadDir, String label) {
    if (seen.add(downloadDir)) {
      results.add((downloadDir, label));
    }
  }

  final defaultPath = await _getAndroidDefaultVideoCachePath();
  add(defaultPath, await _androidStorageLabel(defaultPath, isDefault: true));

  final dirs = await getExternalStorageDirectories();
  if (dirs != null && dirs.isNotEmpty) {
    for (final dir in dirs) {
      final downloadDir = path.join(dir.path, PathUtils.downloadDir);
      add(downloadDir, await _androidStorageLabel(downloadDir));
    }
  } else {
    final dir = await getExternalStorageDirectory();
    if (dir != null) {
      final downloadDir = path.join(dir.path, PathUtils.downloadDir);
      add(downloadDir, await _androidStorageLabel(downloadDir));
    }
  }
  return results;
}

Future<String> _androidStorageLabel(
  String downloadDirPath, {
  bool isDefault = false,
}) async {
  if (!downloadDirPath.startsWith('/storage/')) {
    return isDefault ? '应用内部（默认位置）' : '应用内部';
  }

  final isPrimary =
      downloadDirPath.contains('/storage/emulated/0/') ||
      downloadDirPath.contains('/storage/self/primary/');
  if (isPrimary) {
    return isDefault ? '内部存储（默认位置）' : '内部存储';
  }

  final uuidMatch = RegExp(
    r'/storage/([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})/',
  ).firstMatch(downloadDirPath);
  final uuid = uuidMatch?.group(1);
  final desc = await _getAndroidStorageVolumeDescription(uuid: uuid);
  final volumeLabel = desc?.trim();

  if (volumeLabel != null && volumeLabel.isNotEmpty) {
    return isDefault ? '外部存储（默认位置，$volumeLabel）' : '外部存储（$volumeLabel）';
  }
  return isDefault ? '外部存储（默认位置）' : '外部存储';
}

String _androidVideoCacheCodename(String downloadDirPath) {
  if (!downloadDirPath.startsWith('/storage/')) {
    return '应用内部';
  }
  final isPrimary =
      downloadDirPath.contains('/storage/emulated/0/') ||
      downloadDirPath.contains('/storage/self/primary/');
  return isPrimary ? '内部存储' : '外部存储';
}

Future<String?> _getAndroidStorageVolumeDescription({String? uuid}) async {
  if (uuid == null || uuid.isEmpty) return null;
  try {
    return PiliAndroidHelper.getStorageVolumeDescription(uuid);
  } catch (_) {
    return null;
  }
}

Future<void> _applyDownloadPath(
  String newPath, {
  required VoidCallback setState,
  required bool persist,
}) async {
  try {
    final dir = Directory(newPath);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    downloadPath = dir.path;
    setState();
    Get.find<DownloadService>().initDownloadList();

    if (persist) {
      await GStorage.setting.put(SettingBoxKey.downloadPath, downloadPath);
    } else {
      await GStorage.setting.delete(SettingBoxKey.downloadPath);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('download path error: $e');
    SmartDialog.showToast('设置失败：$e');
  }
}

void _showTouchSlopDialog(BuildContext context, VoidCallback setState) {
  String initialValue = Pref.touchSlopH.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('横向滑动阈值'),
      content: TextFormField(
        autofocus: true,
        initialValue: initialValue,
        keyboardType: const .numberWithOptions(decimal: true),
        onChanged: (value) => initialValue = value,
        inputFormatters: FilteringText.decimal,
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
          onPressed: () async {
            try {
              final val = double.parse(initialValue);
              Get.back();
              touchSlopH = val;
              await GStorage.setting.put(SettingBoxKey.touchSlopH, val);
              setState();
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

Future<void> _showRefreshDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('刷新指示器高度'),
      min: 10.0,
      max: 100.0,
      divisions: 9,
      value: Pref.refreshDisplacement,
    ),
  );
  if (res != null) {
    displacement = res;
    await GStorage.setting.put(SettingBoxKey.refreshDisplacement, res);
    if (WidgetsBinding.instance.rootElement case final context?) {
      context.visitChildElements(_visitor);
    }
    setState();
  }
}

void _visitor(Element context) {
  if (!context.mounted) return;
  if (context.widget is RefreshIndicator) {
    context.markNeedsBuild();
  } else {
    context.visitChildren(_visitor);
  }
}

Future<void> _showFavDialog(BuildContext context) async {
  if (Accounts.main.isLogin) {
    final res = await FavHttp.allFavFolders(Accounts.main.mid);
    if (res case Success(:final response)) {
      final list = response.list;
      if (list == null || list.isEmpty) {
        return;
      }
      final quickFavId = Pref.quickFavId;
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          clipBehavior: Clip.hardEdge,
          title: const Text('选择默认收藏夹'),
          contentPadding: const EdgeInsets.only(top: 5, bottom: 18),
          content: SingleChildScrollView(
            child: RadioGroup(
              onChanged: (value) {
                Get.back();
                GStorage.setting.put(SettingBoxKey.quickFavId, value);
                SmartDialog.showToast('设置成功');
              },
              groupValue: quickFavId,
              child: Column(
                children: list
                    .map(
                      (item) => RadioListTile(
                        toggleable: true,
                        dense: true,
                        title: Text(item.title),
                        value: item.id,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      );
    } else {
      res.toast();
    }
  }
}

Future<void> _showReplyCountDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('连接重试次数'),
      min: 0,
      max: 8,
      divisions: 8,
      precise: 0,
      value: Pref.retryCount.toDouble(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.retryCount, res.toInt());
    setState();
    SmartDialog.showToast('重启生效');
  }
}

Future<void> _showReplyDelayDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('连接重试间隔'),
      min: 0,
      max: 1000,
      divisions: 10,
      precise: 0,
      value: Pref.retryDelay.toDouble(),
      suffix: 'ms',
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.retryDelay, res.toInt());
    setState();
    SmartDialog.showToast('重启生效');
  }
}

void _showProxyDialog(BuildContext context) {
  String systemProxyHost = Pref.systemProxyHost;
  String systemProxyPort = Pref.systemProxyPort;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('设置代理'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          TextFormField(
            initialValue: systemProxyHost,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '请输入Host，使用 . 分割',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
            ),
            onChanged: (e) => systemProxyHost = e,
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: systemProxyPort,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '请输入Port',
              border: OutlineInputBorder(borderRadius: .all(.circular(6))),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (e) => systemProxyPort = e,
          ),
        ],
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
            Get.back();
            GStorage.setting.put(
              SettingBoxKey.systemProxyHost,
              systemProxyHost,
            );
            GStorage.setting.put(
              SettingBoxKey.systemProxyPort,
              systemProxyPort,
            );
          },
          child: const Text('确认'),
        ),
      ],
    ),
  );
}

void _showCacheDialog(BuildContext context, VoidCallback setState) {
  String valueStr = '';
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('最大缓存大小'),
      content: TextField(
        maxLength: 6,
        autofocus: true,
        onChanged: (value) => valueStr = value,
        keyboardType: TextInputType.number,
        inputFormatters: FilteringText.decimal,
        decoration: const InputDecoration(suffixText: 'MB'),
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
          onPressed: () async {
            try {
              final val = num.parse(valueStr);
              Get.back();
              await GStorage.setting.put(
                SettingBoxKey.maxCacheSize,
                val * 1024 * 1024,
              );
              setState();
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
