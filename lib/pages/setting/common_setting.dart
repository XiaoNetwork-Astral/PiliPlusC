import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:material_ui/material_ui.dart';

class CommonSetting extends StatefulWidget {
  const CommonSetting({
    super.key,
    required this.settingType,
    this.showAppBar = true,
    this.highlightTitle,
    this.highlightRequest = 0,
  });

  final bool showAppBar;
  final SettingType settingType;

  /// 进入页面后需要定位并闪烁高亮的设置项标题
  final String? highlightTitle;

  /// 每次搜索跳转时递增，保证重复点击同一项也能再次闪烁
  final int highlightRequest;

  @override
  State<CommonSetting> createState() => _CommonSettingState();
}

class _CommonSettingState extends State<CommonSetting> {
  late EdgeInsets padding;
  late List<SettingsModel> settings;
  List<GlobalKey<_SettingHighlightState>> _itemKeys = const [];
  int? _highlightIndex;
  bool _highlightScheduled = false;
  int _highlightGeneration = 0;

  void _initSetting({required bool rebuildKeys}) {
    settings = widget.settingType.settings;
    if (rebuildKeys || _itemKeys.length != settings.length) {
      _itemKeys = List.generate(
        settings.length,
        (_) => GlobalKey<_SettingHighlightState>(),
      );
    }
    _highlightIndex = _findHighlightIndex();
    _highlightScheduled = false;
    _highlightGeneration++;
  }

  int? _findHighlightIndex() {
    final title = widget.highlightTitle;
    if (title == null) return null;
    final index = settings.indexWhere((item) => item.effectiveTitle == title);
    return index == -1 ? null : index;
  }

  void _scheduleHighlight() {
    final index = _highlightIndex;
    if (index == null || _highlightScheduled) return;
    _highlightScheduled = true;
    final generation = _highlightGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _highlightGeneration) return;
      final itemContext = _itemKeys[index].currentContext;
      if (itemContext == null) return;
      await Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      if (!mounted || generation != _highlightGeneration) return;
      final highlightState = _itemKeys[index].currentState;
      if (highlightState != null) {
        await highlightState.flash();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initSetting(rebuildKeys: true);
    _scheduleHighlight();
  }

  @override
  void didUpdateWidget(CommonSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settingType != oldWidget.settingType ||
        widget.highlightTitle != oldWidget.highlightTitle ||
        widget.highlightRequest != oldWidget.highlightRequest) {
      _initSetting(
        rebuildKeys: widget.settingType != oldWidget.settingType,
      );
      _scheduleHighlight();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    return SimpleScaffold(
      appBar: showAppBar ? AppBar(title: Text(widget.settingType.title)) : null,
      body: SingleChildScrollView(
        key: ValueKey(widget.settingType),
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < settings.length; i++)
              _SettingHighlight(
                key: _itemKeys[i],
                child: settings[i].widget,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingHighlight extends StatefulWidget {
  const _SettingHighlight({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<_SettingHighlight> createState() => _SettingHighlightState();
}

class _SettingHighlightState extends State<_SettingHighlight> {
  static const _flashCount = 3;
  static const _flashOn = Duration(milliseconds: 220);
  static const _flashOff = Duration(milliseconds: 260);

  final _inkKey = GlobalKey();
  InkHighlight? _highlight;
  bool _flashing = false;
  bool _active = true;

  @override
  void deactivate() {
    _active = false;
    _highlight?.dispose();
    _highlight = null;
    super.deactivate();
  }

  Future<void> flash() async {
    if (_flashing || !_active) return;
    final inkContext = _inkKey.currentContext;
    if (inkContext == null) return;
    final referenceBox = inkContext.findRenderObject();
    if (referenceBox is! RenderBox) return;

    _flashing = true;
    final controller = Material.of(inkContext);
    final color = Theme.of(context).highlightColor;
    final textDirection = Directionality.of(inkContext);
    for (var i = 0; i < _flashCount; i++) {
      if (!_active || !mounted) break;
      late final InkHighlight highlight;
      highlight = InkHighlight(
        controller: controller,
        referenceBox: referenceBox,
        color: color,
        textDirection: textDirection,
        onRemoved: () {
          if (identical(_highlight, highlight)) {
            _highlight = null;
          }
        },
      );
      _highlight = highlight;
      await Future<void>.delayed(_flashOn);
      if (!_active || !mounted) break;
      highlight.deactivate();
      await Future<void>.delayed(_flashOff);
    }
    _highlight = null;
    _flashing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: KeyedSubtree(
        key: _inkKey,
        child: widget.child,
      ),
    );
  }
}
