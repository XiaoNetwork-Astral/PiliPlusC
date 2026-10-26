import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';
import 'package:PiliPlus/pages/cognitive_filter/widgets.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// AI 屏蔽的生效范围：每个适用面一个开关
class AiSurfacePage extends StatefulWidget {
  const AiSurfacePage({super.key});

  @override
  State<AiSurfacePage> createState() => _AiSurfacePageState();
}

class _AiSurfacePageState extends State<AiSurfacePage> {
  late Set<FilterSurface> _surfaces;

  @override
  void initState() {
    super.initState();
    _surfaces = Pref.cfAiSurfaces;
  }

  void _toggle(FilterSurface surface, bool value) {
    final next = Set<FilterSurface>.of(_surfaces);
    if (value) {
      next.add(surface);
    } else {
      next.remove(surface);
    }
    Pref.cfAiSurfaces = next;
    setState(() => _surfaces = next);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 100;
    return SimpleScaffold(
      appBar: AppBar(title: const Text('生效范围')),
      body: ViewSafeArea(
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            for (final surface in FilterSurface.values)
              CfSwitchTile(
                title: surface.label,
                value: _surfaces.contains(surface),
                onChanged: (value) => _toggle(surface, value),
              ),
          ],
        ),
      ),
    );
  }
}
