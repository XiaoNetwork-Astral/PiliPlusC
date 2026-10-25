import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/setting/models/dyn_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/reply_settings.dart';
import 'package:material_ui/material_ui.dart';

/// 评论、动态、视频屏蔽的子页，列出与规则无关的保留设置项
class _SettingsSubPage extends StatelessWidget {
  const _SettingsSubPage({required this.title, required this.settings});

  final String title;
  final List<SettingsModel> settings;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: Text(title)),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            for (final item in settings) item.widget,
          ],
        ),
      ),
    );
  }
}

/// 评论屏蔽
class ReplyRuleSubPage extends StatelessWidget {
  const ReplyRuleSubPage({super.key});

  @override
  Widget build(BuildContext context) =>
      _SettingsSubPage(title: '评论屏蔽', settings: replyBlockSettings);
}

/// 动态屏蔽
class DynRuleSubPage extends StatelessWidget {
  const DynRuleSubPage({super.key});

  @override
  Widget build(BuildContext context) =>
      _SettingsSubPage(title: '动态屏蔽', settings: dynBlockSettings);
}

/// 视频屏蔽
class VideoRuleSubPage extends StatelessWidget {
  const VideoRuleSubPage({super.key});

  @override
  Widget build(BuildContext context) =>
      _SettingsSubPage(title: '视频屏蔽', settings: videoBlockSettings);
}
