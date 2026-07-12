import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_palettes.dart';
import '../theme/theme_controller.dart';
import 'menu_wheel.dart' show WheelItem;

/// An interactive 3D icon cloud: the menu items sit on a sphere that slowly
/// rotates on its own, can be dragged in any direction (with momentum), and
/// any icon can be tapped to open it. The item facing the front is highlighted
/// and shown in the readout below — the 3D sibling of [MenuWheel], driven by
/// the same [WheelItem] list.
class IconCloud3D extends StatefulWidget {
  const IconCloud3D({super.key, required this.items, this.transparent = false});

  final List<WheelItem> items;

  /// When true the surrounding globe (gradient background + rim + shadow) is
  /// dropped so the icons float on a transparent background, and the icon /
  /// label colours switch to dark tones for contrast on the light page.
  final bool transparent;

  @override
  State<IconCloud3D> createState() => _IconCloud3DState();
}

class _IconCloud3DState extends State<IconCloud3D>
    with SingleTickerProviderStateMixin {
  AppPalette get _pal => ThemeController.instance.palette;
  Color get _ink => _pal.heroFrom;
  Color get _gold => _pal.secondary;
  Color get _goldDeep => _pal.primary;
  Color get _cream => _pal.soft;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// Unit vectors of each item on the sphere (Fibonacci distribution).
  late List<List<double>> _base;

  /// Accumulated rotation matrix (3x3, row-major).
  List<double> _m = [1, 0, 0, 0, 1, 0, 0, 0, 1];

  // Angular velocity (rad/s) around the X and Y axes.
  double _vx = 0;
  double _vy = 0.35; // gentle idle spin
  bool _dragging = false;
  Duration _lastDragAt = Duration.zero;
  final _clock = Stopwatch()..start();

  int _front = 0;
  Duration _lastHapticAt = Duration.zero;

  int get _n => widget.items.length;

  @override
  void initState() {
    super.initState();
    _computeBase();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(IconCloud3D old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) _computeBase();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _computeBase() {
    // Fibonacci sphere: evenly spreads N points over the sphere surface.
    const golden = 2.399963229728653; // pi * (3 - sqrt(5))
    _base = [
      for (var i = 0; i < _n; i++)
        () {
          final y = _n == 1 ? 0.0 : 1 - 2 * (i + 0.5) / _n;
          final r = math.sqrt(math.max(0, 1 - y * y));
          final t = i * golden;
          return [r * math.cos(t), y, r * math.sin(t)];
        }(),
    ];
  }

  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    if (dt <= 0 || _dragging || _n == 0) return;
    // Momentum decays back to the gentle idle spin.
    final blend = math.min(1.0, 1.4 * dt);
    _vx += (0 - _vx) * blend;
    _vy += (0.35 - _vy) * blend;
    _applyRotation(_vx * dt, _vy * dt);
    if (mounted) setState(() {});
  }

  /// Rotates the accumulated matrix by [ax] around X then [ay] around Y.
  void _applyRotation(double ax, double ay) {
    if (ax == 0 && ay == 0) return;
    final cx = math.cos(ax), sx = math.sin(ax);
    final cy = math.cos(ay), sy = math.sin(ay);
    // R = Ry(ay) * Rx(ax)
    final r = [cy, sx * sy, cx * sy, 0.0, cx, -sx, -sy, sx * cy, cx * cy];
    final m = _m;
    _m = [
      r[0] * m[0] + r[1] * m[3] + r[2] * m[6],
      r[0] * m[1] + r[1] * m[4] + r[2] * m[7],
      r[0] * m[2] + r[1] * m[5] + r[2] * m[8],
      r[3] * m[0] + r[4] * m[3] + r[5] * m[6],
      r[3] * m[1] + r[4] * m[4] + r[5] * m[7],
      r[3] * m[2] + r[4] * m[5] + r[5] * m[8],
      r[6] * m[0] + r[7] * m[3] + r[8] * m[6],
      r[6] * m[1] + r[7] * m[4] + r[8] * m[7],
      r[6] * m[2] + r[7] * m[5] + r[8] * m[8],
    ];
  }

  List<double> _rotated(int i) {
    final b = _base[i];
    final m = _m;
    return [
      m[0] * b[0] + m[1] * b[1] + m[2] * b[2],
      m[3] * b[0] + m[4] * b[1] + m[5] * b[2],
      m[6] * b[0] + m[7] * b[1] + m[8] * b[2],
    ];
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = true;
    _vx = 0;
    _vy = 0;
    _lastDragAt = _clock.elapsed;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    const k = 0.0075; // px -> radians
    final ay = d.delta.dx * k;
    final ax = -d.delta.dy * k;
    final now = _clock.elapsed;
    final dt = (now - _lastDragAt).inMicroseconds / 1e6;
    if (dt > 0) {
      _vx = ax / dt;
      _vy = ay / dt;
    }
    _lastDragAt = now;
    _applyRotation(ax, ay);
    setState(() {});
    _hapticIfFrontChanged();
  }

  void _onPanEnd(DragEndDetails d) {
    _dragging = false;
    _vx = _vx.clamp(-8.0, 8.0);
    _vy = _vy.clamp(-8.0, 8.0);
  }

  void _spin() {
    _vy = 6 + math.Random().nextDouble() * 4;
    _vx = (math.Random().nextDouble() - 0.5) * 2;
  }

  void _hapticIfFrontChanged() {
    if (_n == 0) return;
    var best = 0;
    var bestZ = -2.0;
    for (var i = 0; i < _n; i++) {
      final z = _rotated(i)[2];
      if (z > bestZ) {
        bestZ = z;
        best = i;
      }
    }
    if (best != _front) {
      _front = best;
      final now = _clock.elapsed;
      if (now - _lastHapticAt > const Duration(milliseconds: 80)) {
        _lastHapticAt = now;
        HapticFeedback.selectionClick();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox.shrink();

    // Project every item and find the front-most one.
    final projected = <(int, double, double, double)>[];
    var front = 0;
    var frontZ = -2.0;
    for (var i = 0; i < _n; i++) {
      final p = _rotated(i);
      projected.add((i, p[0], p[1], p[2]));
      if (p[2] > frontZ) {
        frontZ = p[2];
        front = i;
      }
    }
    _front = front;
    // Paint back-to-front so near icons draw (and hit-test) on top.
    projected.sort((a, b) => a.$4.compareTo(b.$4));
    final selItem = widget.items[front];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        const reserve = 138.0; // readout + buttons + hint below the globe
        var s = math.min(maxW - 8, 340.0);
        if (constraints.maxHeight.isFinite) {
          s = math.min(s, constraints.maxHeight - reserve);
        }
        s = s.clamp(150.0, 360.0);
        final radius = s * 0.36;
        const box = 64.0;

        return Column(
          mainAxisSize: constraints.maxHeight.isFinite
              ? MainAxisSize.max
              : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Container(
                width: s,
                height: s,
                decoration: widget.transparent
                    ? null
                    : BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_pal.heroFrom, _pal.heroTo],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(s / 2),
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.55),
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final p in projected)
                      _cloudItem(p.$1, p.$2, p.$3, p.$4, s, radius, box,
                          p.$1 == front),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              selItem.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: _ink,
              ),
            ),
            if (selItem.sub.isNotEmpty)
              Text(
                selItem.sub,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A8578)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _spin,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _goldDeep,
                    side: BorderSide(color: _gold),
                  ),
                  icon: const Icon(Icons.threed_rotation_rounded, size: 18),
                  label: const Text('Spin'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: selItem.onTap,
                  style: FilledButton.styleFrom(backgroundColor: _goldDeep),
                  icon: const Icon(Icons.touch_app_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
              'Drag the globe in any direction — tap an icon to open it.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8A8578)),
            ),
          ],
        );
      },
    );
  }

  Widget _cloudItem(
    int i,
    double x,
    double y,
    double z,
    double s,
    double radius,
    double box,
    bool selected,
  ) {
    final depth = (z + 1) / 2; // 0 back .. 1 front
    final scale = 0.55 + 0.45 * depth;
    final opacity = 0.30 + 0.70 * depth;
    final cx = s / 2 + x * radius;
    final cy = s / 2 - y * radius;
    final item = widget.items[i];

    // On the transparent variant the icons sit on the light page, so use dark
    // tones for contrast; on the globe they sit on a dark gradient (cream).
    final tr = widget.transparent;
    final unselBg = tr
        ? _gold.withValues(alpha: 0.12)
        : _cream.withValues(alpha: 0.16);
    final unselBorder = tr
        ? _gold.withValues(alpha: 0.75)
        : _gold.withValues(alpha: 0.5);
    final unselIcon = tr ? _goldDeep : _cream;
    final labelColor = selected
        ? (tr ? _goldDeep : _gold)
        : (tr ? _ink : _cream);
    final labelShadows = tr
        ? const <Shadow>[]
        : const [Shadow(color: Colors.black54, blurRadius: 2)];
    return Positioned(
      left: cx - box / 2,
      top: cy - box / 2,
      width: box,
      height: box,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: item.onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _gold : unselBg,
                    border: Border.all(
                      color: selected ? (tr ? _goldDeep : _cream) : unselBorder,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    item.icon,
                    size: 21,
                    color: selected ? _ink : unselIcon,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: box,
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                      shadows: labelShadows,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
