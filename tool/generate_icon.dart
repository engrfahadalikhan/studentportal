// Generates the app launcher icon: a white graduation cap on the indigo→teal
// brand gradient. Produces three PNGs in assets/ that flutter_launcher_icons
// turns into every Android density (+ adaptive icon):
//   app_icon.png     — full icon (gradient + cap), legacy / round
//   app_icon_bg.png  — gradient only (adaptive background)
//   app_icon_fg.png  — cap on transparent, padded (adaptive foreground)
//
// Run:  dart run tool/generate_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

const int size = 1024;

// Brand colors — elegant black + gold (matches the app theme).
final _indigo = [27, 24, 19]; // #1B1813 warm near-black (gradient start)
final _teal = [201, 162, 39]; // #C9A227 bright gold (gradient end)
final _white = img.ColorRgba8(255, 248, 224, 255); // warm cream cap

void main() {
  Directory('assets').createSync(recursive: true);

  // 1) Full icon: gradient + cap.
  final full = img.Image(width: size, height: size, numChannels: 4);
  _fillGradient(full);
  _drawCap(full, cx: 512, cyBoard: 430, s: 1.0);
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(full));

  // 2) Adaptive background: gradient only.
  final bg = img.Image(width: size, height: size, numChannels: 4);
  _fillGradient(bg);
  File('assets/app_icon_bg.png').writeAsBytesSync(img.encodePng(bg));

  // 3) Adaptive foreground: cap on transparent, kept inside the safe zone.
  final fg = img.Image(width: size, height: size, numChannels: 4);
  img.fill(fg, color: img.ColorRgba8(0, 0, 0, 0));
  _drawCap(fg, cx: 512, cyBoard: 488, s: 0.72);
  File('assets/app_icon_fg.png').writeAsBytesSync(img.encodePng(fg));

  stdout.writeln('Wrote assets/app_icon.png, app_icon_bg.png, app_icon_fg.png');
}

void _fillGradient(img.Image image) {
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final t = (x + y) / (2.0 * (size - 1));
      final r = (_indigo[0] + (_teal[0] - _indigo[0]) * t).round();
      final g = (_indigo[1] + (_teal[1] - _indigo[1]) * t).round();
      final b = (_indigo[2] + (_teal[2] - _indigo[2]) * t).round();
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

void _drawCap(img.Image image, {required double cx, required double cyBoard, required double s}) {
  final wb = 250.0 * s; // board half-width
  final hb = 120.0 * s; // board half-height

  // Mortarboard (flat diamond).
  img.fillPolygon(
    image,
    vertices: [
      img.Point(cx, cyBoard - hb),
      img.Point(cx + wb, cyBoard),
      img.Point(cx, cyBoard + hb),
      img.Point(cx - wb, cyBoard),
    ],
    color: _white,
  );

  // Cap / head piece hanging below the board (trapezoid).
  final capTopY = cyBoard + 18 * s;
  final capBotY = cyBoard + 200 * s;
  img.fillPolygon(
    image,
    vertices: [
      img.Point(cx - 162 * s, capTopY),
      img.Point(cx + 162 * s, capTopY),
      img.Point(cx + 120 * s, capBotY),
      img.Point(cx - 120 * s, capBotY),
    ],
    color: _white,
  );

  // Tassel: cord from the centre button to the board's right, then hanging.
  // Drawn before the button so the button stays a clean circle on top.
  final tx = cx + wb * 0.84;
  img.drawLine(
    image,
    x1: cx.round(),
    y1: cyBoard.round(),
    x2: tx.round(),
    y2: (cyBoard - 6 * s).round(),
    color: _white,
    thickness: 14 * s,
    antialias: true,
  );
  img.drawLine(
    image,
    x1: tx.round(),
    y1: (cyBoard - 6 * s).round(),
    x2: tx.round(),
    y2: (cyBoard + 150 * s).round(),
    color: _white,
    thickness: 14 * s,
    antialias: true,
  );
  // Tassel knob.
  img.fillRect(
    image,
    x1: (tx - 22 * s).round(),
    y1: (cyBoard + 150 * s).round(),
    x2: (tx + 22 * s).round(),
    y2: (cyBoard + 210 * s).round(),
    color: _white,
    radius: (14 * s).round(),
  );

  // Button on the board centre — brand-colored dot, drawn last so it's clean.
  img.fillCircle(
    image,
    x: cx.round(),
    y: cyBoard.round(),
    radius: (28 * s).round(),
    color: img.ColorRgba8(_indigo[0], _indigo[1], _indigo[2], 255),
  );
}
