import 'dart:math';

/// How hard the bowling is.
///
/// The original changed two things with difficulty — how fast the ball arrives
/// and how unpredictable it is — and this keeps both. Wickets in hand change
/// too, so a harder match is also a shorter one.
enum CricketDifficulty { easy, medium, hard }

extension CricketDifficultyInfo on CricketDifficulty {
  String get label => switch (this) {
    CricketDifficulty.easy => 'Easy',
    CricketDifficulty.medium => 'Medium',
    CricketDifficulty.hard => 'Hard',
  };

  String get blurb => switch (this) {
    CricketDifficulty.easy => 'Slow ball, 8 wickets',
    CricketDifficulty.medium => 'Quicker, 5 wickets',
    CricketDifficulty.hard => 'Fast and wild, 3 wickets',
  };

  int get wickets => switch (this) {
    CricketDifficulty.easy => 8,
    CricketDifficulty.medium => 5,
    CricketDifficulty.hard => 3,
  };

  /// Milliseconds from the bowler's release to the ball reaching the stumps.
  int get flightMs => switch (this) {
    CricketDifficulty.easy => 1500,
    CricketDifficulty.medium => 1150,
    CricketDifficulty.hard => 880,
  };

  /// How far off a straight line the ball may pitch, 0-1.
  double get lineSpread => switch (this) {
    CricketDifficulty.easy => 0.35,
    CricketDifficulty.medium => 0.62,
    CricketDifficulty.hard => 0.85,
  };

  /// Ball-to-ball variation in flight time, as a fraction.
  double get paceSpread => switch (this) {
    CricketDifficulty.easy => 0.08,
    CricketDifficulty.medium => 0.16,
    CricketDifficulty.hard => 0.26,
  };
}

/// What one shot produced.
enum ShotOutcome { six, four, three, two, single, dot, bowled, caught }

extension ShotOutcomeInfo on ShotOutcome {
  int get runs => switch (this) {
    ShotOutcome.six => 6,
    ShotOutcome.four => 4,
    ShotOutcome.three => 3,
    ShotOutcome.two => 2,
    ShotOutcome.single => 1,
    ShotOutcome.dot => 0,
    ShotOutcome.bowled => 0,
    ShotOutcome.caught => 0,
  };

  bool get isWicket => this == ShotOutcome.bowled || this == ShotOutcome.caught;

  /// The shout the original put in a black box in the middle of the screen.
  String get shout => switch (this) {
    ShotOutcome.six => 'SIX!',
    ShotOutcome.four => 'FOUR!',
    ShotOutcome.three => 'THREE',
    ShotOutcome.two => 'TWO',
    ShotOutcome.single => 'SINGLE',
    ShotOutcome.dot => 'NO RUN',
    ShotOutcome.bowled => 'BOWLED!',
    ShotOutcome.caught => 'CAUGHT!',
  };
}

/// One delivery, decided before the bowler starts running in.
class Delivery {
  const Delivery({
    required this.flightMs,
    required this.line,
    required this.bouncePoint,
  });

  /// How long this ball takes from release to the stumps.
  final int flightMs;

  /// Where it pitches across the pitch, -1 (leg) to 1 (off).
  final double line;

  /// How far down the pitch it bounces, 0 (at the batter) to 1 (at the bowler).
  /// Only drives where the red marker is drawn; it does not change the timing.
  final double bouncePoint;

  static Delivery next(CricketDifficulty difficulty, Random rng) {
    final wobble = 1 + (rng.nextDouble() * 2 - 1) * difficulty.paceSpread;
    return Delivery(
      flightMs: (difficulty.flightMs * wobble).round(),
      line: (rng.nextDouble() * 2 - 1) * difficulty.lineSpread,
      bouncePoint: 0.28 + rng.nextDouble() * 0.34,
    );
  }
}

/// The moment in the ball's flight where bat should meet ball.
///
/// Slightly before the stumps, because a batter plays the ball in front of
/// their pads rather than on top of the wicket.
const double idealContact = 0.86;

/// How generous the timing is, as a fraction of the ball's flight.
///
/// Only two numbers matter, and difficulty changes only these two. Everything
/// else about a shot -- how far it goes, whether it is in the air, how many
/// runs it is worth -- follows from them, so the player is being asked exactly
/// one question ("when?") and it is scored the same way every time.
class TimingWindows {
  const TimingWindows({required this.boundary, required this.survive});

  /// Time it this well and the ball reaches the rope.
  final double boundary;

  /// Beyond this the batter has missed badly enough to be out.
  final double survive;

  static TimingWindows of(CricketDifficulty difficulty) => switch (difficulty) {
    CricketDifficulty.easy => const TimingWindows(
      boundary: 0.130,
      survive: 0.380,
    ),
    CricketDifficulty.medium => const TimingWindows(
      boundary: 0.095,
      survive: 0.310,
    ),
    CricketDifficulty.hard => const TimingWindows(
      boundary: 0.070,
      survive: 0.245,
    ),
  };
}

/// Where the rope is, in the distance units a shot is measured in.
const double boundaryDistance = 1.0;

/// What the bat actually did to the ball.
///
/// The shot is worked out as a physical event first -- how far, how high, which
/// way -- and the runs are read off that afterwards. Doing it in that order is
/// what makes the field map honest: it draws this, and the scoreboard counts
/// this, so the two cannot disagree.
class Shot {
  const Shot({
    required this.distance,
    required this.airborne,
    required this.angle,
  });

  /// How far the ball travelled. 1.0 is the boundary rope; more than that
  /// cleared it.
  final double distance;

  /// True if it went in the air. Getting slightly under the ball -- playing
  /// fractionally early -- is what lofts it, which is also what makes a six
  /// riskier than a four rather than simply better.
  final bool airborne;

  /// Radians from straight down the ground, negative to the leg side.
  final double angle;

  bool get clearedBoundary => distance >= boundaryDistance;
}

/// A ball nobody offered a shot at.
const Shot _noShot = Shot(distance: 0.06, airborne: false, angle: 0);

/// Work out what happened to the ball.
///
/// [tapAt] is when the player tapped, as a fraction of the ball's flight, so
/// 1.0 is the instant it reaches the stumps. Null means they never played at
/// it.
Shot playShot({
  required double? tapAt,
  required Delivery delivery,
  required CricketDifficulty difficulty,
  ShotAim aim = ShotAim.straight,
}) {
  if (tapAt == null) return _noShot;

  final windows = TimingWindows.of(difficulty);
  final timing = tapAt - idealContact; // negative = early, under the ball
  final error = timing.abs();

  // Distance falls away in two stages: inside the boundary window a shot
  // always reaches the rope and the best ones sail over it; outside, it drops
  // off steadily until the batter has missed altogether.
  double distance;
  if (error <= windows.boundary) {
    distance = boundaryDistance + 0.28 * (1 - error / windows.boundary);
  } else {
    final past =
        (error - windows.boundary) / (windows.survive - windows.boundary);
    distance = boundaryDistance * (1 - past.clamp(0.0, 1.0));
  }

  // A ball pitching wide of the stumps cannot be hit as cleanly, so it does
  // not travel as far. It is a penalty on distance rather than on the runs
  // directly, which means it can cost a boundary but never causes a dismissal
  // on its own.
  distance *= 1 - 0.18 * delivery.line.abs();

  return Shot(
    distance: distance,
    airborne: timing <= 0,
    angle: shotAngle(tapAt: tapAt, delivery: delivery, aim: aim),
  );
}

/// Read the runs off the shot.
///
/// Along the ground over the rope is four, through the air over it is six, and
/// everything short of it is however far the batter got before a fielder cut
/// it off. A ball in the air that lands short of the rope near a fielder is
/// caught -- which is the whole trade for hitting sixes.
ShotOutcome outcomeOf(
  Shot shot, {
  required double? tapAt,
  required CricketDifficulty difficulty,
  required Delivery delivery,
  List<FieldPosition> field = standardField,
}) {
  if (tapAt == null) return ShotOutcome.bowled;

  final windows = TimingWindows.of(difficulty);
  if ((tapAt - idealContact).abs() > windows.survive) {
    // Swung and missed by a distance. A wild heave at a wide one loops to a
    // fielder; anything straighter crashes into the stumps.
    return delivery.line.abs() > 0.55 ? ShotOutcome.caught : ShotOutcome.bowled;
  }

  if (shot.clearedBoundary) {
    return shot.airborne ? ShotOutcome.six : ShotOutcome.four;
  }

  if (shot.airborne) {
    final catcher = field[nearestFielder(shot.angle, field: field)];
    final underIt =
        (catcher.radius - shot.distance).abs() < 0.14 &&
        (catcher.angle - shot.angle).abs() < 0.34;
    if (underIt) return ShotOutcome.caught;
  }

  // Short of the rope: the runs are simply how far it got.
  if (shot.distance >= 0.72) return ShotOutcome.three;
  if (shot.distance >= 0.48) return ShotOutcome.two;
  if (shot.distance >= 0.22) return ShotOutcome.single;
  return ShotOutcome.dot;
}

/// The scoreboard: runs, wickets and how far through the innings we are.
class Innings {
  Innings({required this.difficulty, this.maxOvers = 5});

  final CricketDifficulty difficulty;
  final int maxOvers;

  int runs = 0;
  int wickets = 0;
  int balls = 0;

  static const ballsPerOver = 6;

  int get maxWickets => difficulty.wickets;
  int get overs => balls ~/ ballsPerOver;
  int get ballInOver => balls % ballsPerOver;

  /// "4.1" — the format every cricket scoreboard uses.
  String get oversText => '$overs.$ballInOver';
  String get scoreText => '$runs/$wickets';

  bool get isOver => wickets >= maxWickets || balls >= maxOvers * ballsPerOver;

  /// Apply a shot and return it, so callers can animate what just happened.
  ShotOutcome record(ShotOutcome outcome) {
    runs += outcome.runs;
    if (outcome.isWicket) wickets++;
    balls++;
    return outcome;
  }

  /// Give the batter one more life without touching the score.
  ///
  /// Used by the rewarded continue, which is why it does not reset anything
  /// else: the innings resumes exactly where it stopped.
  void pardonLastWicket() {
    if (wickets > 0) wickets--;
  }
}

/// Where a fielder stands, in the radar's polar coordinates.
///
/// [angle] is radians from straight down the ground, negative to the leg side
/// and positive to the off side. [radius] is 0 at the pitch and 1 at the rope.
class FieldPosition {
  const FieldPosition(this.name, this.angle, this.radius);

  final String name;
  final double angle;
  final double radius;
}

/// A standard field, near enough to the original's spread of dots.
///
/// Nine fielders plus a keeper: enough that every direction has someone
/// plausible near it, and sparse enough that the gaps are visible on the
/// radar — the gaps are the point, since a player who can see them starts
/// aiming rather than just tapping.
const standardField = <FieldPosition>[
  FieldPosition('Keeper', 3.05, 0.16),
  FieldPosition('Slip', 2.70, 0.22),
  FieldPosition('Point', 1.45, 0.52),
  FieldPosition('Cover', 0.95, 0.60),
  FieldPosition('Mid off', 0.40, 0.55),
  FieldPosition('Mid on', -0.40, 0.55),
  FieldPosition('Midwicket', -0.95, 0.60),
  FieldPosition('Square leg', -1.45, 0.52),
  FieldPosition('Fine leg', -2.55, 0.88),
  FieldPosition('Long on', -0.30, 0.92),
  FieldPosition('Deep cover', 1.15, 0.90),
];

/// The eight directions a shot can be aimed in, as the keypad laid them out.
///
/// Straight is up the ground past the bowler; the leg side is to the left of a
/// right-hander and the off side to the right; and the two behind-square
/// options are the glance and the cut that go past the keeper.
enum ShotAim {
  straight('Straight', 0.0),
  midOn('Mid on', -0.75),
  legSide('Leg side', -1.5),
  fineLeg('Fine leg', -2.35),
  behind('Behind', 3.05),
  thirdMan('Third man', 2.35),
  offSide('Off side', 1.5),
  midOff('Mid off', 0.75);

  const ShotAim(this.label, this.angle);

  final String label;

  /// Radians from straight down the ground, negative to the leg side.
  final double angle;

  /// The aim closest to the direction the player swiped.
  ///
  /// [swipe] is the drag vector in screen space, where up the screen is
  /// straight down the ground — so the player swipes toward where they want
  /// the ball to go, which needs no explaining.
  static ShotAim fromSwipe(double dx, double dy) {
    // Too small to be a deliberate direction: a plain tap plays it straight.
    if (dx * dx + dy * dy < 900) return ShotAim.straight;
    final swipeAngle = atan2(dx, -dy); // 0 = up the screen
    var best = ShotAim.straight;
    var bestGap = double.infinity;
    for (final aim in ShotAim.values) {
      // Compare on the circle so straight and behind do not look far apart.
      var gap = (aim.angle - swipeAngle).abs();
      if (gap > pi) gap = 2 * pi - gap;
      if (gap < bestGap) {
        bestGap = gap;
        best = aim;
      }
    }
    return best;
  }
}

/// Which way the ball actually went, in radians from straight.
///
/// The player aims and the aim dominates — being able to place the ball is the
/// point of having a direction control at all. Timing and the line it pitched
/// on only bend it a little, so a shot played early still drags squarer and a
/// wide one still goes with the angle, without the game overruling where the
/// player pointed.
double shotAngle({
  required double tapAt,
  required Delivery delivery,
  ShotAim aim = ShotAim.straight,
}) {
  final timing = tapAt - idealContact;
  final drift = timing * 1.3 + delivery.line * 0.22;
  final angle = aim.angle + drift;
  // Wrap into -pi..pi so 'behind' stays behind rather than folding around.
  return atan2(sin(angle), cos(angle));
}

/// The fielder standing closest to where the ball was hit.
///
/// Used to decide who chases it on the radar. Returns the index into
/// [standardField]; the ball's outcome is already settled by then, so this is
/// about showing the player what happened, not re-judging it.
int nearestFielder(double angle, {List<FieldPosition> field = standardField}) {
  var best = 0;
  var bestGap = double.infinity;
  for (var i = 0; i < field.length; i++) {
    final gap = (field[i].angle - angle).abs();
    if (gap < bestGap) {
      bestGap = gap;
      best = i;
    }
  }
  return best;
}
