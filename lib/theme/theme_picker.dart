import 'package:flutter/material.dart';

import 'app_palettes.dart';
import 'theme_controller.dart';

/// A small icon button that opens the appearance sheet. Drop it into any app
/// bar / header. Tapping it reveals the theme colors + light/dark mode.
class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key, this.color, this.tooltip = 'Appearance'});

  /// Icon tint. Pass white when placed on a dark hero; leave null on light bars.
  final Color? color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: () => showAppearanceSheet(context),
      icon: Icon(Icons.palette_outlined, color: color),
    );
  }
}

/// Opens a bottom sheet to pick the brand theme color + light / dark mode.
Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _AppearanceSheet(),
  );
}

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final controller = ThemeController.instance;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Pick a theme color.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                const _Label('THEME COLOR'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final palette in kAppPalettes)
                      _SwatchButton(
                        palette: palette,
                        selected: controller.palette.id == palette.id,
                        onTap: () => controller.setPalette(palette),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? palette.primary : scheme.outline,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: palette.brandGradient,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 24)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            palette.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
