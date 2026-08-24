import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quirkade/features/cricket/game/cricket_engine.dart';

Delivery _straight({int flightMs = 1000}) =>
    Delivery(flightMs: flightMs, line: 0.0, bouncePoint: 0.4);

Delivery _wide({int flightMs = 1000}) =>
    Delivery(flightMs: flightMs, line: 0.9, bouncePoint: 0.4);

void main() {
  ShotOutcome judge(
    double? tapAt,
    Delivery delivery,
    CricketDifficulty difficulty,
  ) => outcomeOf(
    playShot(tapAt: tapAt, delivery: delivery, difficulty: difficulty),
    tapAt: tapAt,
    delivery: delivery,
    difficulty: difficulty,
  );

  group('judging a shot', () {
    test('not playing at the ball is bowled', () {
      expect(
        judge(null, _straight(), CricketDifficulty.easy),
        ShotOutcome.bowled,
      );
    });

    test('over the rope in the air is six, along the ground is four', () {
      // The only difference between these two is a hair of timing: getting
      // under the ball lofts it. Both cleared the boundary.
      final lofted = playShot(
        tapAt: idealContact - 0.01,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
      );
      final grounded = playShot(
        tapAt: idealContact + 0.01,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
      );
      expect(lofted.airborne, isTrue);
      expect(grounded.airborne, isFalse);
      expect(lofted.clearedBoundary, isTrue);
      expect(grounded.clearedBoundary, isTrue);
      expect(
        judge(idealContact - 0.01, _straight(), CricketDifficulty.easy),
        ShotOutcome.six,
      );
      expect(
        judge(idealContact + 0.01, _straight(), CricketDifficulty.easy),
        ShotOutcome.four,
      );
    });

    test('runs short of the rope come from how far it got', () {
      // Walking the timing out from perfect should walk the runs down without
      // ever jumping back up.
      var last = 7;
      for (var error = 0.0; error < 0.38; error += 0.02) {
        final runs = judge(
          idealContact + error,
          _straight(),
          CricketDifficulty.easy,
        ).runs;
        expect(
          runs,
          lessThanOrEqualTo(last),
          reason: 'runs rose again at error $error',
        );
        last = runs;
      }
      expect(last, 0, reason: 'the worst surviving shot scores nothing');
    });

    test('the same timing travels less as difficulty rises', () {
      const tap = idealContact + 0.06;
      final easy = playShot(
        tapAt: tap,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
      );
      final medium = playShot(
        tapAt: tap,
        delivery: _straight(),
        difficulty: CricketDifficulty.medium,
      );
      final hard = playShot(
        tapAt: tap,
        delivery: _straight(),
        difficulty: CricketDifficulty.hard,
      );
      expect(easy.distance, greaterThan(medium.distance));
      expect(medium.distance, greaterThan(hard.distance));
    });

    test('a wide ball shortens the shot without dismissing anyone', () {
      final straight = playShot(
        tapAt: idealContact,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
      );
      final wide = playShot(
        tapAt: idealContact,
        delivery: _wide(),
        difficulty: CricketDifficulty.easy,
      );
      expect(wide.distance, lessThan(straight.distance));
      expect(
        judge(idealContact, _wide(), CricketDifficulty.easy).isWicket,
        isFalse,
      );
    });

    test('swinging wildly is out — bowled if straight, caught if wide', () {
      const miles = idealContact - 0.6;
      expect(
        judge(miles, _straight(), CricketDifficulty.easy),
        ShotOutcome.bowled,
      );
      expect(judge(miles, _wide(), CricketDifficulty.easy), ShotOutcome.caught);
    });

    test('a well-timed shot always scores, on any line', () {
      // The rule that keeps the game fair: a player who timed it well is
      // never dismissed for a thing they could not see coming.
      for (final line in [-0.9, -0.4, 0.0, 0.4, 0.9]) {
        final ball = Delivery(flightMs: 1000, line: line, bouncePoint: 0.4);
        final outcome = judge(idealContact, ball, CricketDifficulty.hard);
        expect(outcome.isWicket, isFalse, reason: 'line $line');
        expect(outcome.runs, greaterThan(0), reason: 'line $line');
      }
    });

    test('a ball nobody played at goes nowhere', () {
      final shot = playShot(
        tapAt: null,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
      );
      expect(shot.distance, lessThan(0.1));
      expect(shot.clearedBoundary, isFalse);
    });
  });

  group('shot direction', () {
    test('middling it goes straight back down the ground', () {
      expect(
        shotAngle(tapAt: idealContact, delivery: _straight()).abs(),
        lessThan(0.05),
      );
    });

    test('early is leg side, late is off side', () {
      expect(
        shotAngle(tapAt: idealContact - 0.15, delivery: _straight()),
        lessThan(0),
      );
      expect(
        shotAngle(tapAt: idealContact + 0.15, delivery: _straight()),
        greaterThan(0),
      );
    });

    test('the nearest fielder to a straight drive is a straight fielder', () {
      final chaser = standardField[nearestFielder(0.0)];
      expect(chaser.angle.abs(), lessThan(0.5));
    });
  });

  group('the ball is where the game says it is', () {
    test('the bat meets the ball exactly at the ideal contact point', () {
      // REGRESSION. The painter drew the ball level with the bat at 96% of
      // its flight while the judging measured against 86%, so timing a shot
      // by eye was ~160ms late by construction and every ball came back
      // BOWLED. Both now derive from the same geometry; this is the assertion
      // that keeps them derived from it.
      expect(ballPitchPosition(idealContact), closeTo(batContactAt, 1e-9));
    });

    test('the ball starts at the bowler and ends past the keeper', () {
      expect(ballPitchPosition(0), ballStartsAt);
      expect(ballPitchPosition(1), closeTo(keeperAt, 1e-9));
    });

    test('a shot timed by eye scores, on every difficulty', () {
      for (final difficulty in CricketDifficulty.values) {
        final outcome = judge(idealContact, _straight(), difficulty);
        expect(outcome.isWicket, isFalse, reason: '$difficulty');
        expect(outcome.runs, greaterThan(0), reason: '$difficulty');
      }
    });

    test('being slightly late is a mistimed shot, never a missed one', () {
      // The ball carries through to the keeper, which is what leaves room to
      // be late. Without that the window shut at the instant of contact and
      // a tap a fraction late scored as if no shot had been played at all.
      for (final difficulty in CricketDifficulty.values) {
        for (final late in [0.05, 0.12, 0.20]) {
          expect(
            judge(idealContact + late, _straight(), difficulty),
            isNot(ShotOutcome.bowled),
            reason: '$difficulty, $late late',
          );
        }
      }
    });

    test('there is always reachable time left after contact', () {
      // A tap cannot land after the flight phase ends, so if contact sat too
      // close to 1.0 the late half of every window would be unreachable.
      expect(1.0 - idealContact, greaterThan(0.15));
    });
  });

  group('aiming the shot', () {
    test('a plain tap plays it straight', () {
      expect(ShotAim.fromSwipe(0, 0), ShotAim.straight);
      // A few pixels of finger wobble is not a direction.
      expect(ShotAim.fromSwipe(4, -6), ShotAim.straight);
    });

    test('you swipe toward where you want the ball to go', () {
      // Screen space: up is straight down the ground, left is the leg side.
      expect(ShotAim.fromSwipe(0, -120), ShotAim.straight);
      expect(ShotAim.fromSwipe(-120, 0), ShotAim.legSide);
      expect(ShotAim.fromSwipe(120, 0), ShotAim.offSide);
      expect(ShotAim.fromSwipe(0, 120), ShotAim.behind);
      expect(ShotAim.fromSwipe(-90, -90), ShotAim.midOn);
      expect(ShotAim.fromSwipe(90, -90), ShotAim.midOff);
      expect(ShotAim.fromSwipe(-90, 90), ShotAim.fineLeg);
      expect(ShotAim.fromSwipe(90, 90), ShotAim.thirdMan);
    });

    test('the aim decides the direction, not the timing', () {
      // Timing bends the shot a little, but a leg-side swipe must never come
      // out on the off side — placing the ball is the whole point of aiming.
      for (final aim in ShotAim.values) {
        for (final error in [-0.2, -0.05, 0.0, 0.05, 0.2]) {
          final angle = shotAngle(
            tapAt: idealContact + error,
            delivery: _straight(),
            aim: aim,
          );
          var gap = (angle - aim.angle).abs();
          if (gap > pi) gap = 2 * pi - gap;
          expect(gap, lessThan(0.45), reason: '${aim.label} at error $error');
        }
      }
    });

    test('the aim carries through to the shot the radar draws', () {
      final legward = playShot(
        tapAt: idealContact,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
        aim: ShotAim.legSide,
      );
      final offward = playShot(
        tapAt: idealContact,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
        aim: ShotAim.offSide,
      );
      expect(legward.angle, lessThan(0));
      expect(offward.angle, greaterThan(0));
      // Aim changes where it goes, never how well it was struck.
      expect(legward.distance, closeTo(offward.distance, 0.0001));
    });

    test('aiming into a gap beats aiming at a fielder', () {
      // The reason the field map is on screen while the ball is coming.
      final atFielder = playShot(
        tapAt: idealContact - 0.16,
        delivery: _straight(),
        difficulty: CricketDifficulty.easy,
        aim: ShotAim.offSide,
      );
      final chaser = standardField[nearestFielder(atFielder.angle)];
      expect((chaser.angle - atFielder.angle).abs(), lessThan(1.0));
    });
  });

  group('the radar agrees with the scoreboard', () {
    test('every boundary the scoreboard counts also cleared the rope', () {
      // The radar draws Shot.distance and the scoreboard counts outcomeOf on
      // the same Shot, so this is the property that keeps them honest.
      for (final difficulty in CricketDifficulty.values) {
        for (var error = -0.5; error <= 0.5; error += 0.01) {
          final tap = idealContact + error;
          final shot = playShot(
            tapAt: tap,
            delivery: _straight(),
            difficulty: difficulty,
          );
          final outcome = outcomeOf(
            shot,
            tapAt: tap,
            delivery: _straight(),
            difficulty: difficulty,
          );
          final isBoundary =
              outcome == ShotOutcome.four || outcome == ShotOutcome.six;
          if (isBoundary) {
            expect(
              shot.clearedBoundary,
              isTrue,
              reason: '$outcome drawn short of the rope at error $error',
            );
          }
          if (outcome.runs > 0 && !isBoundary) {
            expect(
              shot.distance,
              lessThan(boundaryDistance),
              reason: 'a ${outcome.runs} drawn past the rope',
            );
          }
        }
      }
    });
  });

  group('the innings', () {
    test('counts overs the way a scoreboard does', () {
      final innings = Innings(difficulty: CricketDifficulty.easy);
      for (var i = 0; i < 7; i++) {
        innings.record(ShotOutcome.single);
      }
      expect(innings.oversText, '1.1');
      expect(innings.scoreText, '7/0');
    });

    test('ends when the wickets run out', () {
      final innings = Innings(difficulty: CricketDifficulty.hard);
      expect(innings.maxWickets, 3);
      for (var i = 0; i < 3; i++) {
        expect(innings.isOver, isFalse);
        innings.record(ShotOutcome.bowled);
      }
      expect(innings.isOver, isTrue);
    });

    test('ends when the overs run out', () {
      final innings = Innings(difficulty: CricketDifficulty.easy, maxOvers: 5);
      for (var i = 0; i < 30; i++) {
        innings.record(ShotOutcome.dot);
      }
      expect(innings.isOver, isTrue);
      expect(innings.oversText, '5.0');
    });

    test('a pardoned wicket resumes the innings where it stopped', () {
      final innings = Innings(difficulty: CricketDifficulty.hard);
      innings.record(ShotOutcome.four);
      for (var i = 0; i < 3; i++) {
        innings.record(ShotOutcome.bowled);
      }
      expect(innings.isOver, isTrue);
      innings.pardonLastWicket();
      expect(innings.isOver, isFalse);
      expect(innings.runs, 4, reason: 'the score must survive the pardon');
      expect(innings.balls, 4, reason: 'and so must the balls already bowled');
    });
  });

  group('deliveries', () {
    test('a harder difficulty bowls faster and wider', () {
      final rng = Random(7);
      var easyTotal = 0.0;
      var hardTotal = 0.0;
      var easyLine = 0.0;
      var hardLine = 0.0;
      for (var i = 0; i < 200; i++) {
        final easy = Delivery.next(CricketDifficulty.easy, rng);
        final hard = Delivery.next(CricketDifficulty.hard, rng);
        easyTotal += easy.flightMs;
        hardTotal += hard.flightMs;
        easyLine += easy.line.abs();
        hardLine += hard.line.abs();
      }
      expect(hardTotal, lessThan(easyTotal));
      expect(hardLine, greaterThan(easyLine));
    });

    test('the ball always pitches somewhere on the pitch', () {
      final rng = Random(3);
      for (final difficulty in CricketDifficulty.values) {
        for (var i = 0; i < 100; i++) {
          final ball = Delivery.next(difficulty, rng);
          expect(ball.bouncePoint, inInclusiveRange(0.0, 1.0));
          expect(ball.line.abs(), lessThanOrEqualTo(1.0));
          expect(ball.flightMs, greaterThan(300));
        }
      }
    });
  });
}
