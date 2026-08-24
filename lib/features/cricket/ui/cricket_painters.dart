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
    final base = _point(batContactAt - 0.015, 0.34, size);
    final h = size.height * 0.074;
    final w = size.width * 0.0115;
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
  /// Stands at the contact point the judging uses, beside the stumps rather
  /// than on top of them, at a size that leaves the pitch readable. The first
  /// pass drew this figure half again as large and centred on the strip, which
  /// buried the crease lines and the stumps behind it.
  void _paintBatter(Canvas canvas, Size size) {
    final feet = _point(batContactAt, -0.34, size);
    final unit = size.height * 0.019;

    void block(double x, double y, double w, double h, Color c) => _rect(
      canvas,
      Rect.fromLTWH(feet.dx + unit * x, feet.dy - unit * y, unit * w, unit * h),
      c,
    );

    // Back leg, front leg.
    block(0, 2.7, 0.95, 2.7, PitchColors.batterDark);
    block(1.35, 2.4, 0.95, 2.4, PitchColors.batterDark);
    // Torso, then the shoulder nearest us.
    block(-0.15, 5.4, 2.6, 2.9, PitchColors.batter);
    block(2.0, 5.1, 0.75, 1.9, PitchColors.batterDark);
    // Helmet and grille.
    block(0.3, 6.9, 1.9, 1.6, PitchColors.helmet);
    block(0.3, 5.9, 1.9, 0.35, PitchColors.batterDark);

    // The bat hangs from the hands and sweeps through on contact. At rest it
    // points down at the crease, which is what a batter waiting looks like.
    canvas.save();
    canvas.translate(feet.dx + unit * 2.35, feet.dy - unit * 3.7);
    canvas.rotate(0.18 + swing * 2.3);
    _rect(
      canvas,
      Rect.fromLTWH(-unit * 0.2, -unit * 1.3, unit * 0.4, unit * 1.4),
      PitchColors.batterDark,
    );
    _rect(
      canvas,
      Rect.fromLTWH(-unit * 0.42, unit * 0.05, unit * 0.84, unit * 2.7),
      PitchColors.bat,
    );
    canvas.restore();
  }

  /// The bowler, running in from the top of the mark and delivering.
  ///
  /// The approach covers real ground rather than shuffling on the spot — a
  /// bowler who does not visibly arrive gives the player no cue that a ball is
  /// about to be released.
  void _paintBowler(Canvas canvas, Size size) {
    final t = 1.34 - runUp * 0.30;
    final feet = _point(t, 0.5, size);
    final unit = size.height * 0.0105;

    void block(double x, double y, double w, double h, Color c) => _rect(
      canvas,
      Rect.fromLTWH(feet.dx + unit * x, feet.dy - unit * y, unit * w, unit * h),
      c,
    );

    // Legs scissor while approaching, then plant for the delivery stride.
    final running = runUp > 0.02 && runUp < 0.88;
    final stride = running ? sin(runUp * pi * 7) * 0.9 : 0.7;
    block(-stride, 2.4, 0.85, 2.4, PitchColors.bowlerDark);
    block(stride + 0.9, 2.4, 0.85, 2.4, PitchColors.bowlerDark);
    block(-0.15, 5.1, 2.2, 2.8, PitchColors.bowler);
    block(0.25, 6.5, 1.5, 1.5, PitchColors.batter);

    // The arm comes over the top through the last of the run-up.
    final arm = ((runUp - 0.66) / 0.30).clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(feet.dx + unit * 1.0, feet.dy - unit * 4.9);
    canvas.rotate(-2.7 + arm * 2.5);
    _rect(
      canvas,
      Rect.fromLTWH(-unit * 0.28, 0, unit * 0.65, unit * 2.5),
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
    // The one source of truth for where the ball is, shared with the judging.
    final t = ballPitchPosition(p);
    // Drifts from the middle onto the line it pitches on, then holds it.
    final pitched = ((1 - t) / (1 - d.bouncePoint)).clamp(0.0, 1.0);
    final straightening = t < d.bouncePoint
        ? ((d.bouncePoint - t) / max(d.bouncePoint - batContactAt, 0.05)).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final u = (d.line * pitched * (1 - 0.5 * straightening)).clamp(-1.0, 1.0);
    final base = _point(t.clamp(keeperAt, ballStartsAt), u, size);

    // A hop off the pitch, so the ball is not sliding along a line.
    final afterBounce = t < d.bouncePoint
        ? ((d.bouncePoint - t) / max(d.bouncePoint - batContactAt, 0.05)).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final hop = sin(afterBounce * pi) * size.height * 0.03;
    final radius = size.width * (0.008 + 0.028 * p.clamp(0.0, 1.0));
    final centre = Offset(base.dx, base.dy - hop);

    // A shadow on the pitch under the ball: without it a hopping ball reads
    // as one that simply moved up the screen, which is the wrong direction.
    canvas.drawOval(
      Rect.fromCenter(center: base, width: radius * 2.1, height: radius * 0.9),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawCircle(centre, radius, Paint()..color = PitchColors.ball);
    // A seam, so a fast ball still reads as a cricket ball.
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius * 0.72),
      -0.6,
      1.2,
      false,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, radius * 0.22),
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
