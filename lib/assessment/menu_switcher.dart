import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';
import 'icon_cloud.dart';
import 'menu_wheel.dart';

/// Which presentation the home menu uses.
/// - [wheel]: the spinning gold/black wheel.
/// - [cloud]: the 3D icon cloud inside a solid globe.
/// - [cloudClear]: the 3D icon cloud on a transparent background (no globe).
enum MenuStyle { wheel, cloud, cloudClear }

/// Remembers whether the user prefers the spinning [MenuWheel] or the 3D
/// [IconCloud3D] home menu (persisted on-device, shared by every dashboard).
class MenuStyleController extends ChangeNotifier {
  MenuStyleController._();
  static final MenuStyleController instance = MenuStyleController._();

  static const _key = 'home_menu_style_v1';
  MenuStyle _style = MenuStyle.wheel;
  bool _loaded = false;

  MenuStyle get style => _style;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _style = _fromKey(p.getString(_key));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> set(MenuStyle s) async {
    if (_style == s) return;
    _style = s;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, _toKey(s));
    } catch (_) {}
  }

  static MenuStyle _fromKey(String? v) {
    switch (v) {
      case 'cloud':
        return MenuStyle.cloud;
      case 'clear':
        return MenuStyle.cloudClear;
      default:
        return MenuStyle.wheel;
    }
  }

  static String _toKey(MenuStyle s) {
    switch (s) {
      case MenuStyle.cloud:
        return 'cloud';
      case MenuStyle.cloudClear:
        return 'clear';
      case MenuStyle.wheel:
        return 'wheel';
    }
  }
}

/// The home menu with a small toggle to switch between the spinning wheel and
/// the interactive 3D icon cloud. Drop-in replacement for [MenuWheel] — takes
/// the same [WheelItem] list and fills the height it is given.
class MenuSwitcher extends StatefulWidget {
  const MenuSwitcher({super.key, required this.items});

  final List<WheelItem> items;

  @override
  State<MenuSwitcher> createState() => _MenuSwitcherState();
}

class _MenuSwitcherState extends State<MenuSwitcher> {
  final _ctrl = MenuStyleController.instance;

  @override
  void initState() {
    super.initState();
    _ctrl.load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = ThemeController.instance.palette;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final style = _ctrl.style;
        final Widget menu;
        switch (style) {
          case MenuStyle.wheel:
            menu = MenuWheel(items: widget.items);
            break;
          case MenuStyle.cloud:
            menu = IconCloud3D(items: widget.items);
            break;
          case MenuStyle.cloudClear:
            menu = IconCloud3D(items: widget.items, transparent: true);
            break;
        }
        return Column(
          children: [
            _StyleToggle(
              style: style,
              gold: pal.secondary,
              ink: pal.heroFrom,
              onSelect: _ctrl.set,
            ),
            const SizedBox(height: 4),
            Expanded(child: menu),
          ],
        );
      },
    );
  }
}

class _StyleToggle extends StatelessWidget {
  const _StyleToggle({
    required this.style,
    required this.gold,
    required this.ink,
    required this.onSelect,
  });

  final MenuStyle style;
  final Color gold;
  final Color ink;
  final ValueChanged<MenuStyle> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            icon: Icons.blur_circular_rounded,
            label: 'Wheel',
            selected: style == MenuStyle.wheel,
            onTap: () => onSelect(MenuStyle.wheel),
          ),
          _seg(
            icon: Icons.threed_rotation_rounded,
            label: '3D',
            selected: style == MenuStyle.cloud,
            onTap: () => onSelect(MenuStyle.cloud),
          ),
          _seg(
            icon: Icons.bubble_chart_rounded,
            label: 'Clear',
            selected: style == MenuStyle.cloudClear,
            onTap: () => onSelect(MenuStyle.cloudClear),
          ),
        ],
      ),
    );
  }

  Widget _seg({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? gold : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? ink : gold),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? ink : gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
