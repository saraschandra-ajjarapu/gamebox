import 'dart:math';
import 'package:flutter/material.dart';
import '../game/cricket_engine.dart';

/// The palette, read off the original screens.
class PitchColors {
  static const grassDark = Color(0xFF1F7E33);
  static const grassLight = Color(0xFF2A9040);
  static const grassDeep = Color(0xFF145C24);
  static const strip = Color(0xFFE7C3AE);
  static const stripEdge = Color(0xFFD3A78F);
  static const crease = Color(0xFFFFFFFF);
  static const stumpsNear = Color(0xFFFBF3E2);
  static const stumpsShadow = Color(0xFF8C6A50);
  static const stumpsFar = Color(0xFFD9A441);
  static const batter = Color(0xFF7E3B2F);
  static const batterDark = Color(0xFF5A2820);
  static const helmet = Color(0xFF23305E);
  static const bat = Color(0xFFE0C08A);
  static const bowler = Color(0xFF3E5A9E);
  static const bowlerDark = Color(0xFF2A3E70);
  static const ball = Color(0xFFD93A2B);
}

/// The view down the pitch from behind the batter.
///
/// Everything is drawn from two numbers: `t`, the distance up the pitch where
/// 0 is the batter's crease and 1 is the bowler's, and `u`, the position
/// across it from -1 to 1. The pitch narrows toward the top, so a thing's size
/// and its horizontal spread both come from how far up it sits — which is what
/// makes a flat canvas read as a pitch receding away from you.
class PitchPainter extends CustomPainter {
  PitchPainter({
    required this.delivery,
    required this.ballProgress,
    required this.runUp,
    required this.swing,
    required this.showMarker,
  });

  /// The ball currently being bowled, or null between deliveries.
  final Delivery? delivery;

  /// 0 at release, 1 when the ball reaches the stumps. Null when not in flight.
  final double? ballProgress;

  /// The bowler's approach, 0 (top of the mark) to 1 (at the crease).
  final double runUp;

  /// The bat's swing, 0 (waiting) to 1 (followed through).
  final double swing;

  final bool showMarker;

  // Where the pitch sits on screen.
  static const _farY = 0.235;
  static const _nearY = 0.995;
  static const _farHalf = 0.055;
  static const _nearHalf = 0.295;
  static const _horizonY = 0.075;

  double _yFor(double t, Size size) {
    // Non-linear so the far half compresses the way a receding plane does.
    final c = pow(t.clamp(0.0, 1.2), 0.72).toDouble();
    return size.height * (_nearY + (_farY - _nearY) * c);
  }

  /// Half the pitch width at a given screen y — linear in y, which is what
  /// makes the edges straight lines and the whole thing a clean trapezoid.
  double _halfWidthAtY(double y, Size size) {
    final f = ((y - size.height * _nearY) / (size.height * (_farY - _nearY)))
        .clamp(0.0, 1.4);
    return size.width * (_nearHalf + (_farHalf - _nearHalf) * f);
  }

  Offset _point(double t, double u, Size size) {
    final y = _yFor(t, size);
    return Offset(size.width / 2 + u * _halfWidthAtY(y, size), y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintOutfield(canvas, size);
    _paintPitch(canvas, size);
    _paintCreases(canvas, size);
    _paintFarStumps(canvas, size);
    _paintBowler(canvas, size);
    if (showMarker && delivery != null) _paintBounceMarker(canvas, size);
    _paintNearStumps(canvas, size);
    _paintBatter(canvas, size);
    if (ballProgress != null && delivery != null) _paintBall(canvas, size);
  }

  /// The mown outfield.
  ///
  /// The bands converge on a point far ABOVE the screen rather than on the
  /// horizon. A roller leaves parallel stripes, and in perspective they lean
  /// together only slightly — aiming them at the vanishing point turns the
  /// whole ground into a starburst, which is the one thing the original's
  /// outfield never looks like.
  void _paintOutfield(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PitchColors.grassDark);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * _horizonY),
      Paint()..color = PitchColors.grassDeep,
    );

    final converge = Offset(size.width / 2, -size.height * 2.2);
    final bandWidth = size.width * 0.19;
    final paint = Paint()..color = PitchColors.grassLight;
    for (var i = -6; i <= 6; i += 2) {
      final left = size.width / 2 + i * bandWidth;
      final right = left + bandWidth;
      // Taper each band toward the far convergence point.
      double leanAt(double x, double y) =>
          x +
          (converge.dx - x) * (y - size.height) / (converge.dy - size.height);
      final topY = size.height * _horizonY;
      final path = Path()
        ..moveTo(leanAt(left, topY), topY)
        ..lineTo(leanAt(right, topY), topY)
        ..lineTo(right, size.height)
        ..lineTo(left, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _paintPitch(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(_point(0.0, -1, size).dx, _yFor(0.0, size))
      ..lineTo(_point(1.0, -1, size).dx, _yFor(1.0, size))
      ..lineTo(_point(1.0, 1, size).dx, _yFor(1.0, size))
      ..lineTo(_point(0.0, 1, size).dx, _yFor(0.0, size))
      ..close();
    canvas.drawPath(path, Paint()..color = PitchColors.strip);
    canvas.drawPath(
      path,
      Paint()
        ..color = PitchColors.stripEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintCreases(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PitchColors.crease
      ..style = PaintingStyle.stroke;
    for (final t in const [0.075, 0.9]) {
      final y = _yFor(t, size);
      final half = _halfWidthAtY(y, size) * 1.42;
      paint.strokeWidth = (1 - t) * 3.4 + 1.2;
      canvas.drawLine(
        Offset(size.width / 2 - half, y),
        Offset(size.width / 2 + half, y),
        paint,
      );
    }
    // The batter's popping crease, drawn short like the original's.
    final y = _yFor(0.16, size);
    canvas.drawLine(
      Offset(size.width / 2 - _halfWidthAtY(y, size) * 0.9, y),
      Offset(size.width / 2 + _halfWidthAtY(y, size) * 0.9, y),
      paint..strokeWidth = 2.4,
    );
  }

  void _rect(Canvas canvas, Rect r, Color c) =>
      canvas.drawRect(r, Paint()..color = c);

  void _paintNearStumps(Canvas canvas, Size size) {
    final base = _point(0.03, 0.36, size);
    final h = size.height * 0.088;
    final w = size.width * 0.013;
    for (var i = 0; i < 3; i++) {
      final x = base.dx + i * w * 2.3;
      // Cream stumps on a cream pitch vanish, so each gets a shadow.
      _rect(
        canvas,
        Rect.fromLTWH(x + w * 0.3, base.dy - h, w, h),
        PitchColors.stumpsShadow,
      );
      _rect(
        canvas,
        Rect.fromLTWH(x, base.dy - h, w, h),
        PitchColors.stumpsNear,
      );
    }
    // The bails across the top.
    _rect(
      canvas,
      Rect.fromLTWH(base.dx, base.dy - h - w * 0.6, w * 5.6, w * 0.6),
      PitchColors.stumpsNear,
    );
  }

  void _paintFarStumps(Canvas canvas, Size size) {
    final base = _point(0.93, -0.12, size);
    final h = size.height * 0.026;
    final w = size.width * 0.0055;
    for (var i = 0; i < 3; i++) {
      _rect(
        canvas,
        Rect.fromLTWH(base.dx + i * w * 2.2, base.dy - h, w, h),
        PitchColors.stumpsFar,
      );
    }
  }

  /// The batter, blocked out the way a low-resolution sprite would be.
  ///
  /// Drawn large: this is the figure the player is, and at the size the first
  /// pass used it read as a smudge on the crease rather than a person holding
  /// a bat.
  void _paintBatter(Canvas canvas, Size size) {
    final feet = _point(0.035, -0.46, size);
    final unit = size.height * 0.0235;

    // Back leg, front leg, torso, arms, helmet — each a plain block.
    _rect(
      canvas,
      Rect.fromLTWH(feet.dx, feet.dy - unit * 2.8, unit * 1.05, unit * 2.8),
      PitchColors.batterDark,
    );
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx + unit * 1.5,
        feet.dy - unit * 2.4,
        unit * 1.0,
        unit * 2.4,
      ),
      PitchColors.batterDark,
    );
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx - unit * 0.15,
        feet.dy - unit * 5.6,
        unit * 2.8,
        unit * 3.0,
      ),
      PitchColors.batter,
    );
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx + unit * 2.2,
        feet.dy - unit * 5.2,
        unit * 0.8,
        unit * 1.9,
      ),
      PitchColors.batterDark,
    );
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx + unit * 0.35,
        feet.dy - unit * 7.2,
        unit * 2.1,
        unit * 1.7,
      ),
      PitchColors.helmet,
    );
    // The grille, so the helmet reads as a helmet.
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx + unit * 0.35,
        feet.dy - unit * 6.1,
        unit * 2.1,
        unit * 0.4,
      ),
      PitchColors.batterDark,
    );

    // The bat swings through an arc as the shot is played.
    canvas.save();
    final pivot = Offset(feet.dx + unit * 2.6, feet.dy - unit * 3.6);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-0.25 + swing * 2.6);
    // Handle then blade, so it is a bat rather than a stick.
    _rect(
      canvas,
      Rect.fromLTWH(-unit * 0.22, -unit * 1.5, unit * 0.44, unit * 1.6),
      PitchColors.batterDark,
    );
    _rect(
      canvas,
      Rect.fromLTWH(-unit * 0.45, unit * 0.1, unit * 0.9, unit * 2.9),
      PitchColors.bat,
    );
    canvas.restore();
  }

  /// The bowler at the top of the screen, running in.
  void _paintBowler(Canvas canvas, Size size) {
    final t = 1.16 - runUp * 0.16;
    final feet = _point(t, 0.55, size);
    final unit = size.height * 0.0075;

    // Legs alternate while approaching so the run-up reads as movement.
    final stride = sin(runUp * pi * 6) * unit * 0.9;
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx - stride,
        feet.dy - unit * 2.4,
        unit * 0.9,
        unit * 2.4,
      ),
      PitchColors.bowlerDark,
    );
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx + stride + unit,
        feet.dy - unit * 2.4,
        unit * 0.9,
        unit * 2.4,
      ),
      PitchColors.bowlerDark,
    );
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx - unit * 0.2,
        feet.dy - unit * 5.2,
        unit * 2.4,
        unit * 2.9,
      ),
      PitchColors.bowler,
    );
    _rect(
      canvas,
      Rect.fromLTWH(
        feet.dx + unit * 0.4,
        feet.dy - unit * 6.6,
        unit * 1.6,
        unit * 1.5,
      ),
      PitchColors.batter,
    );

    // The bowling arm comes over as the delivery is released.
    final arm = (runUp - 0.72).clamp(0.0, 0.28) / 0.28;
    canvas.save();
    canvas.translate(feet.dx + unit * 1.1, feet.dy - unit * 5.0);
    canvas.rotate(-2.6 + arm * 2.4);
    _rect(
      canvas,
      Rect.fromLTWH(-unit * 0.3, 0, unit * 0.7, unit * 2.6),
      PitchColors.bowler,
    );
    canvas.restore();
  }

  /// The red X showing where the ball will pitch.
  ///
  /// The original telegraphs the length this way, and it is the only warning
  /// the player gets — without it a fast delivery is pure guesswork.
  void _paintBounceMarker(Canvas canvas, Size size) {
    final d = delivery!;
    final p = _point(d.bouncePoint, d.line, size);
    final r = size.width * 0.018 * (1.4 - d.bouncePoint);
    final paint = Paint()
      ..color = PitchColors.ball
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(p.translate(-r, -r), p.translate(r, r), paint);
    canvas.drawLine(p.translate(r, -r), p.translate(-r, r), paint);
  }

  void _paintBall(Canvas canvas, Size size) {
    final d = delivery!;
    final p = ballProgress!;
    // t runs from the bowler's end down to the batter as the ball travels.
    final t = (1 - p).clamp(0.0, 1.0);
    // The ball drifts from the middle out to the line it pitches on.
    final u = d.line * min(1.0, p / max(d.bouncePoint, 0.05));
    final base = _point(t, u.clamp(-1.0, 1.0), size);

    // A hop after the bounce, so the ball is not just sliding along a line.
    final afterBounce = (p - (1 - d.bouncePoint)).clamp(0.0, 1.0);
    final hop = sin(afterBounce.clamp(0.0, 1.0) * pi) * size.height * 0.035;
    final radius = size.width * (0.008 + 0.026 * p);

    canvas.drawCircle(
      Offset(base.dx, base.dy - hop),
      radius,
      Paint()..color = PitchColors.ball,
    );
  }

  @override
  bool shouldRepaint(covariant PitchPainter old) =>
      old.ballProgress != ballProgress ||
      old.runUp != runUp ||
      old.swing != swing ||
      old.delivery != delivery ||
      old.showMarker != showMarker;
}

/// The overhead field map the original cuts to after a shot.
///
/// Its job is to answer the question the batting view cannot: where did the
/// ball actually go, and who was standing there. The fielders are drawn even
/// before the shot, so the gaps are visible while there is still time to use
/// them.
class FieldRadarPainter extends CustomPainter {
  FieldRadarPainter({
    required this.field,
    required this.shotAngle,
    required this.travel,
    required this.highlight,
  });

  final List<FieldPosition> field;

  /// Radians from straight down the ground; null before a shot is played.
  final double? shotAngle;

  /// How far along its path the ball has travelled, 0 to [travel]'s target.
  final double travel;

  /// Index into [field] of the fielder chasing it, or null.
  final int? highlight;

  Offset _polar(double angle, double radius, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.385;
    final ry = size.height * 0.385;
    return Offset(cx + sin(angle) * radius * rx, cy - cos(angle) * radius * ry);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PitchColors.grassDark);

    // The boundary rope.
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.77,
      height: size.height * 0.77,
    );
    canvas.drawOval(
      oval,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // The pitch, seen from directly above.
    final strip = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.042,
      height: size.height * 0.30,
    );
    canvas.drawRect(strip, Paint()..color = PitchColors.strip);

    // Fielders.
    for (var i = 0; i < field.length; i++) {
      final p = _polar(field[i].angle, field[i].radius, size);
      final isChasing = highlight != null && highlight == i;
      canvas.drawCircle(
        p,
        isChasing ? 5.5 : 4.0,
        Paint()..color = isChasing ? PitchColors.ball : Colors.white,
      );
    }

    // The batter, in the middle where the shot came from.
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2 + size.height * 0.09),
        width: 6,
        height: 10,
      ),
      Paint()..color = PitchColors.helmet,
    );

    if (shotAngle == null || travel <= 0) return;

    // The ball's path, drawn as a line so the direction is unmistakable.
    final from = Offset(size.width / 2, size.height / 2 + size.height * 0.07);
    // A six clears the rope; drawn any further and it leaves the map, which
    // tells the player nothing about where it went.
    final to = _polar(shotAngle!, min(travel, 1.08), size);
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = PitchColors.ball.withValues(alpha: 0.75)
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(to, 5, Paint()..color = PitchColors.ball);
  }

  @override
  bool shouldRepaint(covariant FieldRadarPainter old) =>
      old.shotAngle != shotAngle ||
      old.travel != travel ||
      old.highlight != highlight;
}
