import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quirkade/features/cricket/game/cricket_engine.dart';

/// Plays [balls] deliveries the way a person does: aim for the moment the ball
/// reaches the bat, and miss it by up to [jitterMs] either side.
///
/// Every other cricket test checks one rule in isolation. None of them could
/// answer "is this game playable", which is how a build shipped where every
/// ball came back BOWLED and a later one where every ball was a boundary.
({int runs, int wickets, int balls}) simulate(
  CricketDifficulty difficulty,
  int jitterMs, {
  int balls = 600,
  int seed = 11,
}) {
  final rng = Random(seed);
  var runs = 0;
  var wickets = 0;
  for (var i = 0; i < balls; i++) {
    final ball = Delivery.next(difficulty, rng);
    final phaseMs = ball.flightMs * ballTravel;
    final tap = idealContact + (rng.nextDouble() * 2 - 1) * jitterMs / phaseMs;
    if (tap > 1.0) {
      wickets++; // never got a shot away before the ball passed
      continue;
    }
    final shot = playShot(tapAt: tap, delivery: ball, difficulty: difficulty);
    final outcome = outcomeOf(
      shot,
      tapAt: tap,
      delivery: ball,
      difficulty: difficulty,
    );
    runs += outcome.runs;
    if (outcome.isWicket) wickets++;
  }
  return (runs: runs, wickets: wickets, balls: balls);
}

void main() {
  group('the game is playable', () {
    test('good timing is rewarded and rarely punished', () {
      // ±60ms is a person concentrating. They should score freely. The wicket
      // ceiling rises with difficulty on purpose — on Hard you cannot middle
      // it consistently, so spooning one up is a real risk even when you are
      // watching closely. On Easy it should almost never happen.
      const ceiling = {
        CricketDifficulty.easy: 0.08,
        CricketDifficulty.medium: 0.12,
        CricketDifficulty.hard: 0.15,
      };
      for (final difficulty in CricketDifficulty.values) {
        final r = simulate(difficulty, 60);
        expect(
          r.runs / r.balls,
          greaterThan(1.5),
          reason: '$difficulty scores nothing',
        );
        expect(
          r.wickets / r.balls,
          lessThan(ceiling[difficulty]!),
          reason: '$difficulty punishes good timing',
        );
      }
    });

    test('sloppy timing still gets a game, just a worse one', () {
      // ±200ms is someone not really watching. They should survive a while
      // and score a little — being out every ball is what made build 30
      // unplayable.
      for (final difficulty in CricketDifficulty.values) {
        final r = simulate(difficulty, 200);
        expect(
          r.wickets / r.balls,
          lessThan(0.25),
          reason: '$difficulty is a procession',
        );
        expect(r.runs, greaterThan(0), reason: '$difficulty scores nothing');
      }
    });

    test('timing better scores more, on every difficulty', () {
      for (final difficulty in CricketDifficulty.values) {
        final sharp = simulate(difficulty, 50).runs;
        final ok = simulate(difficulty, 120).runs;
        final sloppy = simulate(difficulty, 260).runs;
        expect(sharp, greaterThan(ok), reason: '$difficulty: sharp vs ok');
        expect(ok, greaterThan(sloppy), reason: '$difficulty: ok vs sloppy');
      }
    });

    test('boundaries are earned, not the default outcome', () {
      // Build 31 gave a boundary on 98% of deliveries at ordinary accuracy,
      // because the window was a fraction of the flight rather than a number
      // of milliseconds. Ordinary accuracy should score, not dominate.
      final r = simulate(CricketDifficulty.easy, 120);
      expect(
        r.runs / r.balls,
        lessThan(4.0),
        reason: 'nearly every ball is going to the rope',
      );
    });

    test('a harder difficulty is actually harder', () {
      const jitter = 120;
      final easy = simulate(CricketDifficulty.easy, jitter).runs;
      final medium = simulate(CricketDifficulty.medium, jitter).runs;
      final hard = simulate(CricketDifficulty.hard, jitter).runs;
      expect(easy, greaterThan(medium));
      expect(medium, greaterThan(hard));
    });

    test('an innings lasts long enough to be a game', () {
      // Five overs is 30 balls. Losing 8 wickets inside that on Easy with
      // ordinary timing would end most innings early.
      final r = simulate(CricketDifficulty.easy, 150, balls: 30);
      expect(
        r.wickets,
        lessThan(CricketDifficulty.easy.wickets),
        reason: 'Easy innings ends before the overs do',
      );
    });
  });
}
