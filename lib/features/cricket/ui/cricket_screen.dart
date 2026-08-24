import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/services/rewarded_ad_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/high_score_dialog.dart';
import '../../../core/widgets/rewarded_continue_button.dart';
import '../game/cricket_engine.dart';
import 'cricket_painters.dart';

/// What the screen is doing right now.
enum _Phase {
  /// Between deliveries — the bowler is walking back.
  waiting,

  /// Running in. Tapping here is too early and is refused rather than punished.
  runUp,

  /// The ball is travelling. Exactly one tap counts.
  flight,

  /// Bat swings, the shout appears.
  resolve,

  /// Cut to the overhead map so the shot's direction is visible.
  radar,

  /// Innings finished.
  done,
}

class CricketScreen extends StatefulWidget {
  const CricketScreen({super.key});

  @override
  State<CricketScreen> createState() => _CricketScreenState();
}

class _CricketScreenState extends State<CricketScreen>
    with SingleTickerProviderStateMixin {
  static const _waitMs = 320;
  static const _runUpMs = 520;
  static const _resolveMs = 420;
  static const _radarMs = 950;

  late final Ticker _ticker;
  final _rng = Random();

  Duration _now = Duration.zero;
  Duration _phaseStart = Duration.zero;
  _Phase _phase = _Phase.waiting;

  CricketDifficulty _difficulty = CricketDifficulty.easy;
  late Innings _innings;

  Delivery? _delivery;
  double? _tapAt;
  ShotAim _aim = ShotAim.straight;
  Shot? _shot;
  double? _shotAngle;
  int? _chaser;
  double _radarTravel = 0;
  Offset _dragFrom = Offset.zero;
  Offset _dragTo = Offset.zero;
  String _flash = '';
  bool _continueUsed = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _innings = Innings(difficulty: _difficulty);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _chooseDifficulty());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int get _phaseMs => switch (_phase) {
    _Phase.waiting => _waitMs,
    _Phase.runUp => _runUpMs,
    _Phase.flight => ((_delivery?.flightMs ?? 1000) * ballTravel).round(),
    _Phase.resolve => _resolveMs,
    _Phase.radar => _radarMs,
    _Phase.done => 1,
  };

  /// How close the ball is to the moment to swing, 0 to 1.
  ///
  /// Peaks exactly at contact and falls away either side, scaled to the
  /// difficulty's own boundary window — so Easy's target glows over a wider
  /// span than Hard's, which is the same generosity the scoring already has.
  double get _strikeHint {
    final delivery = _delivery;
    if (delivery == null || _phase != _Phase.flight) return 0;
    final window = TimingWindows.of(_difficulty).boundaryFraction(delivery);
    final error = (_t - idealContact).abs();
    return (1 - error / (window * 2.4)).clamp(0.0, 1.0);
  }

  /// How far through the current phase we are, 0 to 1.
  double get _t =>
      ((_now - _phaseStart).inMicroseconds / (_phaseMs * 1000)).clamp(0.0, 1.0);

  void _onTick(Duration elapsed) {
    _now = elapsed;
    if (!_started || _phase == _Phase.done) {
      setState(() {});
      return;
    }
    if (_t >= 1.0) {
      _advance();
    } else {
      setState(() {});
    }
  }

  void _enter(_Phase phase) {
    setState(() {
      _phase = phase;
      _phaseStart = _now;
    });
  }

  void _advance() {
    switch (_phase) {
      case _Phase.waiting:
        _delivery = Delivery.next(_difficulty, _rng);
        _tapAt = null;
        _aim = ShotAim.straight;
        _shotAngle = null;
        _chaser = null;
        _radarTravel = 0;
        _flash = '';
        _enter(_Phase.runUp);
      case _Phase.runUp:
        _enter(_Phase.flight);
      case _Phase.flight:
        // The ball has finished. If a shot was started but the finger is
        // still down, honour it with whatever direction it has so far — the
        // timing was already captured at touch-down and throwing it away
        // would score a played shot as if it had never happened.
        if (_tapAt != null) {
          _aim = ShotAim.fromSwipe(
            _dragTo.dx - _dragFrom.dx,
            _dragTo.dy - _dragFrom.dy,
          );
        }
        _resolveBall();
      case _Phase.resolve:
        // The field map earns its interruption when the ball actually went
        // somewhere. Cutting away after a dot ball is a second of watching
        // nothing travel, every time, and that adds up to most of an innings.
        if ((_shot?.distance ?? 0) >= 0.30) {
          _enter(_Phase.radar);
        } else if (_innings.isOver) {
          _finish();
        } else {
          _enter(_Phase.waiting);
        }
      case _Phase.radar:
        if (_innings.isOver) {
          _finish();
        } else {
          _enter(_Phase.waiting);
        }
      case _Phase.done:
        break;
    }
  }

  /// Settle the delivery: judge the timing, score it, and work out where the
  /// ball went so the radar can show it.
  void _resolveBall() {
    final delivery = _delivery!;
    // The shot is a physical event first — how far, how high, which way — and
    // the runs are read off it. The radar draws the same shot, so what the
    // player sees and what the scoreboard counts cannot drift apart.
    final shot = playShot(
      tapAt: _tapAt,
      delivery: delivery,
      difficulty: _difficulty,
      aim: _aim,
    );
    final outcome = outcomeOf(
      shot,
      tapAt: _tapAt,
      delivery: delivery,
      difficulty: _difficulty,
    );
    _innings.record(outcome);

    setState(() {
      _shot = shot;
      _shotAngle = shot.angle;
      _chaser = nearestFielder(shot.angle);
      _flash = outcome.shout;
    });

    HapticFeedback.mediumImpact();
    if (outcome.isWicket) HapticFeedback.heavyImpact();
    _enter(_Phase.resolve);
  }

  /// The player commits to a shot the instant they touch down — that is the
  /// timing — and the direction is whichever way they drag from there.
  ///
  /// Resolving on drag end rather than on touch is what makes both controls
  /// one gesture: a flick is a placed shot, a plain tap is a straight one, and
  /// neither needs a mode or a button.
  void _onTouchDown() {
    if (!_started) return;
    if (_phase == _Phase.runUp) {
      // Refused, not punished. Swinging before the ball is bowled is a
      // mistake the game should teach rather than take a wicket for.
      setState(() => _flash = 'TOO EARLY');
      return;
    }
    if (_phase != _Phase.flight || _tapAt != null) return;
    _tapAt = _t;
  }

  void _onSwipeEnd(Offset delta) {
    if (_phase != _Phase.flight || _tapAt == null) return;
    _aim = ShotAim.fromSwipe(delta.dx, delta.dy);
    _resolveBall();
  }

  Future<void> _finish() async {
    setState(() => _phase = _Phase.done);
    final runs = _innings.runs;
    if (!mounted || runs <= 0) return;
    await HighScoreDialog.submitIfQualifies(
      context: context,
      gameId: 'cricket',
      gameName: 'Cricket Cup',
      score: runs,
      scoreLabel: 'Runs',
    );
  }

  void _restart() {
    setState(() {
      _innings = Innings(difficulty: _difficulty);
      _continueUsed = false;
      _delivery = null;
      _shot = null;
      _tapAt = null;
      _flash = '';
      _started = true;
    });
    _enter(_Phase.waiting);
  }

  /// Give the batter the wicket back and carry on from where they stopped.
  Future<void> _continueAfterAd() async {
    final earned = await RewardedAdService.instance.show();
    if (!earned || !mounted) return;
    setState(() {
      _continueUsed = true;
      _innings.pardonLastWicket();
    });
    _enter(_Phase.waiting);
  }

  Future<void> _chooseDifficulty() async {
    final picked = await showModalBottomSheet<CricketDifficulty>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: _started,
      enableDrag: _started,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: GameTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Choose your innings',
              style: TextStyle(
                color: GameTheme.textPrimary,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Five overs. Tap as the ball reaches you — the closer to the '
              'bat, the further it goes.',
              style: TextStyle(color: GameTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            for (final d in CricketDifficulty.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: d == _difficulty
                          ? GameTheme.accent
                          : GameTheme.border,
                      width: d == _difficulty ? 2 : 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Column(
                    children: [
                      Text(
                        d.label,
                        style: const TextStyle(
                          color: GameTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        d.blurb,
                        style: const TextStyle(
                          color: GameTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _difficulty = picked ?? _difficulty);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    final showRadar = _phase == _Phase.radar;
    // The ball travels out across the radar cut rather than appearing at rest.
    if (showRadar && _shot != null) {
      _radarTravel =
          _shot!.distance * Curves.easeOut.transform(min(1.0, _t * 1.6));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: GameTheme.background,
        title: const Text('Cricket Cup'),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: GameTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Difficulty',
            icon: const Icon(
              Icons.tune_rounded,
              color: GameTheme.textSecondary,
            ),
            onPressed: _chooseDifficulty,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) {
          _dragFrom = details.localPosition;
          _dragTo = details.localPosition;
          _onTouchDown();
        },
        onPanUpdate: (details) => _dragTo = details.localPosition,
        onPanEnd: (_) => _onSwipeEnd(_dragTo - _dragFrom),
        onPanCancel: () => _onSwipeEnd(Offset.zero),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showRadar)
              CustomPaint(
                painter: FieldRadarPainter(
                  field: standardField,
                  shotAngle: _shotAngle,
                  travel: _radarTravel,
                  highlight: _chaser,
                ),
              )
            else
              CustomPaint(
                painter: PitchPainter(
                  delivery: _delivery,
                  // The ball keeps travelling while the bat comes through.
                  // Making it vanish at the instant of the shot was most of
                  // what read as "no animation": the one moment the player is
                  // watching for had nothing in it.
                  ballProgress: switch (_phase) {
                    _Phase.flight => _t,
                    _Phase.resolve =>
                      (_tapAt ?? 1.0) + (1 - (_tapAt ?? 1.0)) * _t,
                    _ => null,
                  },
                  // The bowler stays where he delivered from once the ball
                  // is gone; snapping him back to the top of his mark
                  // mid-delivery was the main thing making this look unbuilt.
                  runUp: switch (_phase) {
                    _Phase.waiting => 0,
                    _Phase.runUp => _t,
                    _ => 1,
                  },
                  swing: _phase == _Phase.resolve
                      ? Curves.easeOutCubic.transform(_t)
                      : 0,
                  showMarker:
                      _phase == _Phase.flight || _phase == _Phase.resolve,
                  strikeHint: _strikeHint,
                ),
              ),

            _Scoreboard(innings: _innings, difficulty: _difficulty),

            // The field map stays on screen while the ball is on its way.
            // Aiming at a gap is only a decision if the gaps are visible in
            // time to use them — showing the field only after the shot would
            // make the direction control guesswork.
            if (!showRadar)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    width: 96,
                    height: 108,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white54),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: CustomPaint(
                      painter: FieldRadarPainter(
                        field: standardField,
                        shotAngle: null,
                        travel: 0,
                        highlight: null,
                      ),
                    ),
                  ),
                ),
              ),

            if (_flash.isNotEmpty && _phase != _Phase.done)
              Center(child: _RetroBanner(text: _flash)),

            // Only on the very first ball of an innings: after that the
            // instruction is in the way of the thing it is explaining.
            if (_phase == _Phase.flight && _innings.balls == 0)
              const Align(
                alignment: Alignment(0, 0.62),
                child: _RetroBanner(text: 'SWIPE TO HIT'),
              ),
            if (_phase == _Phase.flight && _innings.balls == 0)
              const Align(
                alignment: Alignment(0, 0.78),
                child: Text(
                  'tap = straight · swipe where you want it to go',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),

            if (_phase == _Phase.done) _gameOver(),
          ],
        ),
      ),
    );
  }

  Widget _gameOver() {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _RetroBanner(text: 'INNINGS OVER'),
            const SizedBox(height: 18),
            Text(
              _innings.scoreText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            Text(
              '${_innings.oversText} overs · ${_difficulty.label}',
              style: const TextStyle(
                color: GameTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: GameTheme.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 34,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _restart,
              child: const Text(
                'Play again',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
            // Only worth offering when wickets ran out; a completed five overs
            // is finished either way and an extra life would not resume it.
            if (_innings.wickets >= _innings.maxWickets)
              RewardedContinueButton(
                gameOver: true,
                alreadyUsed: _continueUsed,
                onContinue: _continueAfterAd,
                label: 'Watch ad for one more wicket',
              ),
          ],
        ),
      ),
    );
  }
}

/// The scoreboard strip, laid out like the original's: wickets, overs, score.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.innings, required this.difficulty});

  final Innings innings;
  final CricketDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // A dot per wicket still standing, the way the original showed
              // them — a number you have to read is slower than a row you can
              // take in at a glance while a ball is on its way.
              Row(
                children: [
                  for (var i = 0; i < innings.maxWickets; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < innings.maxWickets - innings.wickets
                            ? PitchColors.ball
                            : Colors.white24,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                innings.scoreText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  height: 1.05,
                ),
              ),
              Container(
                width: 62,
                height: 2,
                color: PitchColors.ball,
                margin: const EdgeInsets.symmetric(vertical: 2),
              ),
              Text(
                innings.oversText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The black box with a white border the original put its shouts in.
class _RetroBanner extends StatelessWidget {
  const _RetroBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
