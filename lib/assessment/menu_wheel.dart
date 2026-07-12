import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_palettes.dart';
import '../theme/theme_controller.dart';

/// One selectable spoke on the [MenuWheel].
class WheelItem {
  const WheelItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub = '',
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
}

/// A gold/black rotary menu: the items sit around a wheel, you can flick to
/// spin it (with momentum + snap) and the item under the top pointer is
/// highlighted — but you can also just TAP any item to open it directly.
///
/// It sizes the wheel to the space it is given (put it in an `Expanded`), so
/// the whole menu fits on one screen without scrolling.
class MenuWheel extends StatefulWidget {
  const MenuWheel({super.key, required this.items});

  final List<WheelItem> items;

  @override
  State<MenuWheel> createState() => _MenuWheelState();
}

class _MenuWheelState extends State<MenuWheel>
    with SingleTickerProviderStateMixin {
  // Palette-driven so the wheel follows the app theme (gold, indigo, …) and
  // recolours whenever the palette changes.
  AppPalette get _pal => ThemeController.instance.palette;
  Color get _ink => _pal.heroFrom;
  Color get _segA => _pal.heroFrom;
  Color get _segB => _pal.heroTo;
  Color get _gold => _pal.secondary;
  Color get _goldDeep => _pal.primary;
  Color get _cream => _pal.soft;

  late final AnimationController _ctrl;
  double _angle = 0; // radians; item i is at top when angle == -i*step
  double _lastTouchAngle = 0;
  double _angVel = 0; // rad/sec, for momentum
  Duration _lastMoveAt = Duration.zero;
  Duration _lastTickAt = Duration.zero;
  int? _lastTickIndex;
  final _clock = Stopwatch()..start();

  int get _n => widget.items.length;
  double get _step => 2 * math.pi / _n;

  int get _selected {
    if (_n == 0) return 0;
    final raw = (-_angle / _step).round() % _n;
    return raw < 0 ? raw + _n : raw;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() => _angle = _ctrl.value);
        _tickIfSelectionMoved();
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _touchAngle(Offset local, Size size) =>
      math.atan2(local.dy - size.height / 2, local.dx - size.width / 2);

  void _onPanStart(DragStartDetails d, Size size) {
    _ctrl.stop();
    _angVel = 0;
    _lastTickIndex = _selected;
    _lastTouchAngle = _touchAngle(d.localPosition, size);
    _lastMoveAt = _clock.elapsed;
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    final a = _touchAngle(d.localPosition, size);
    var delta = a - _lastTouchAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    final now = _clock.elapsed;
    final dt = (now - _lastMoveAt).inMicroseconds / 1e6;
    if (dt > 0) _angVel = delta / dt;
    _lastMoveAt = now;
    _lastTouchAngle = a;
    setState(() => _angle += delta);
    _tickIfSelectionMoved();
  }

  void _onPanEnd(DragEndDetails d) {
    _ctrl.value = _angle;
    _lastTickIndex = _selected;
    final v = _angVel.clamp(-40.0, 40.0);
    if (v.abs() < 0.2) {
      _snap();
      return;
    }
    _ctrl.animateWith(FrictionSimulation(0.14, _angle, v)).whenComplete(_snap);
  }

  void _snap() {
    final target = (_angle / _step).roundToDouble() * _step;
    _ctrl.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 0.5, stiffness: 140, damping: 20),
        _angle,
        target,
        _ctrl.velocity,
      ),
    );
  }

  void _flick() {
    _ctrl.stop();
    _ctrl.value = _angle;
    _lastTickIndex = _selected;
    _ctrl
        .animateWith(
          FrictionSimulation(
            0.14,
            _angle,
            12 + math.Random().nextDouble() * 10,
          ),
        )
        .whenComplete(_snap);
  }

  void _tickIfSelectionMoved() {
    if (_n <= 1) return;
    final selected = _selected;
    final previous = _lastTickIndex;
    _lastTickIndex = selected;
    if (previous == null || previous == selected) return;
    final now = _clock.elapsed;
    if (now - _lastTickAt < const Duration(milliseconds: 45)) return;
    _lastTickAt = now;
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
  }

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox.shrink();
    final sel = _selected;
    final selItem = widget.items[sel];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        // Reserve vertical room for the readout + buttons + hint below the
        // disc AND the 14px pointer above it (forgetting the pointer made the
        // column overflow by a few px on short screens).
        const reserve = 152.0;
        var d = math.min(maxW - 8, 340.0);
        if (constraints.maxHeight.isFinite) {
          d = math.min(d, constraints.maxHeight - reserve);
        }
        d = d.clamp(150.0, 360.0);
        final r = d * 0.365; // orbit radius for the item icons

        return Column(
          mainAxisSize: constraints.maxHeight.isFinite
              ? MainAxisSize.max
              : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: d,
              height: d + 14, // room for the pointer above the disc
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    child: CustomPaint(
                      size: const Size(26, 16),
                      painter: _PointerPainter(_gold),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    child: GestureDetector(
                      onPanStart: (e) => _onPanStart(e, Size(d, d)),
                      onPanUpdate: (e) => _onPanUpdate(e, Size(d, d)),
                      onPanEnd: _onPanEnd,
                      child: SizedBox(
                        width: d,
                        height: d,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.rotate(
                              angle: _angle,
                              child: CustomPaint(
                                size: Size(d, d),
                                painter: _DiscPainter(
                                  segments: _n,
                                  segA: _segA,
                                  segB: _segB,
                                  gold: _gold,
                                  goldDeep: _goldDeep,
                                ),
                              ),
                            ),
                            for (var i = 0; i < _n; i++)
                              _positioned(i, r, d, i == sel),
                            _hub(selItem),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
                  onPressed: _flick,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _goldDeep,
                    side: BorderSide(color: _gold),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
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
              'Flick the wheel, or tap any item to open it.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8A8578)),
            ),
          ],
        );
      },
    );
  }

  Widget _positioned(int i, double r, double d, bool selected) {
    final theta = i * _step + _angle; // 0 == top
    final phi = theta - math.pi / 2;
    final cx = d / 2 + r * math.cos(phi);
    final cy = d / 2 + r * math.sin(phi);
    const box = 72.0;
    final item = widget.items[i];
    return Positioned(
      left: cx - box / 2,
      top: cy - box / 2,
      width: box,
      height: box,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        child: AnimatedScale(
          scale: selected ? 1.16 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? _gold : _cream.withValues(alpha: 0.16),
                  border: Border.all(
                    color: selected ? _cream : _gold.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  item.icon,
                  size: 21,
                  color: selected ? _ink : _cream,
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
                    color: selected ? _gold : _cream,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hub(WheelItem selItem) {
    return GestureDetector(
      onTap: selItem.onTap,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _ink,
          border: Border.all(color: _gold, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selItem.icon, color: _gold, size: 26),
            const SizedBox(height: 2),
            Text(
              'OPEN',
              style: TextStyle(
                color: _cream,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  _PointerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color;
}

class _DiscPainter extends CustomPainter {
  _DiscPainter({
    required this.segments,
    required this.segA,
    required this.segB,
    required this.gold,
    required this.goldDeep,
  });

  final int segments;
  final Color segA, segB, gold, goldDeep;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);
    final step = 2 * math.pi / segments;

    for (var i = 0; i < segments; i++) {
      final paint = Paint()..color = i.isEven ? segA : segB;
      final start = -math.pi / 2 - step / 2 + i * step;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..arcTo(rect, start, step, false)
          ..close(),
        paint,
      );
    }

    final spoke = Paint()
      ..color = gold.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (var i = 0; i < segments; i++) {
      final a = -math.pi / 2 - step / 2 + i * step;
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * radius, spoke);
    }

    canvas.drawCircle(
      c,
      radius - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = gold,
    );
    canvas.drawCircle(
      c,
      radius - 8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = goldDeep,
    );
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.segments != segments;
}
