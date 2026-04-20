import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/widgets/high_score_dialog.dart';

class PacManScreen extends StatefulWidget {
  const PacManScreen({super.key});

  @override
  State<PacManScreen> createState() => _PacManScreenState();
}

enum _Dir { up, down, left, right, none }

// Maze tiles:
//   # = wall
//   . = dot
//   o = power pellet
//   (space) = empty path
//   P = pacman spawn
//   G = ghost spawn
// All mazes are 15 cols × 17 rows so rendering math stays constant.
const _mazes = <List<String>>[
  // Level 1: Classic
  [
    '###############',
    '#o.....#.....o#',
    '#.###.#.#.###.#',
    '#.............#',
    '#.###.#.#.###.#',
    '#..#..#.#..#..#',
    '##.#.##.##.#.##',
    '#....G...G....#',
    '##.#.##.##.#.##',
    '#..#.......#..#',
    '#.#.#.###.#.#.#',
    '#.............#',
    '#.###.###.###.#',
    '#o....#P#....o#',
    '#.###.#.#.###.#',
    '#.............#',
    '###############',
  ],
  // Level 2: Cross Quarters
  [
    '###############',
    '#o...........o#',
    '#.##.#.#.#.##.#',
    '#..#.......#..#',
    '##.#.##.##.#.##',
    '#......#......#',
    '#.####.#.####.#',
    '#....G...G....#',
    '#.####.#.####.#',
    '#......#......#',
    '##.#.##.##.#.##',
    '#..#.......#..#',
    '#.##.#.#.#.##.#',
    '#.............#',
    '#.#.#.###.#.#.#',
    '#o.....P.....o#',
    '###############',
  ],
  // Level 3: Open Plaza
  [
    '###############',
    '#o...........o#',
    '#.###.....###.#',
    '#.............#',
    '#.#.#.###.#.#.#',
    '#.............#',
    '##.##.#.#.##.##',
    '#....G...G....#',
    '##.##.###.##.##',
    '#.............#',
    '#.#.#.###.#.#.#',
    '#.............#',
    '#.###.....###.#',
    '#.............#',
    '#.#.#.###.#.#.#',
    '#o.....P.....o#',
    '###############',
  ],
];

const _mazeNames = <String>[
  'Classic',
  'Cross Quarters',
  'Open Plaza',
];

class _Actor {
  int row, col;
  _Dir dir;
  _Actor({required this.row, required this.col, this.dir = _Dir.left});
}

class _Ghost extends _Actor {
  final Color color;
  final int id;
  bool frightened = false;
  bool eaten = false;
  final int spawnRow, spawnCol;
  _Ghost({required this.id, required this.color,
    required super.row, required super.col})
      : spawnRow = row, spawnCol = col;
}

class _PacManScreenState extends State<PacManScreen> {
  static const _cols = 15;
  static const _rows = 17;
  static const _baseTickMs = 230; // relaxed default tick

  late List<List<String>> _tiles;
  late _Actor _pac;
  late List<_Ghost> _ghosts;
  _Dir _pendingDir = _Dir.none;

  int _score = 0;
  int _bestScore = 0;
  int _lives = 3;
  int _level = 1;
  int _dotsRemaining = 0;
  int _initialDots = 0;
  int _frightTicks = 0;
  int _ghostEatChain = 0;

  // Bonus fruit: appears once per level after half the dots are eaten.
  (int, int)? _fruitPos;
  int _fruitTicks = 0;           // remaining ticks until it disappears
  bool _fruitSpawnedThisLevel = false;

  // Level intro banner
  int _levelIntroTicks = 0;      // counts down each tick

  // Ghost throttle — early levels give the player a head start. On level 1,
  // ghosts skip 1 move in every 3 ticks (67% speed); level 2 → 80%; level 3+ full.
  int _tickCounter = 0;

  bool _gameOver = false;
  bool _won = false;
  bool _started = false;

  Timer? _timer;
  Timer? _mouthTimer;
  bool _mouthOpen = true;
  bool _useDpad = false;
  Offset? _swipeStart;

  @override
  void initState() {
    super.initState();
    _loadBest();
    _resetMaze();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _bestScore = prefs.getInt('best_score_pacman') ?? 0);
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score_pacman', _bestScore);
  }

  void _promptHighScore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HighScoreDialog.submitIfQualifies(
        context: context, gameId: 'pacman', gameName: 'Pac-Man', score: _score);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mouthTimer?.cancel();
    super.dispose();
  }

  List<String> get _currentMaze => _mazes[(_level - 1) % _mazes.length];

  String get _currentMazeName => _mazeNames[(_level - 1) % _mazeNames.length];

  void _resetMaze() {
    final maze = _currentMaze;
    _tiles = maze.map((r) {
      return r.split('').map((ch) => ch == 'P' || ch == 'G' ? ' ' : ch).toList();
    }).toList();

    _dotsRemaining = 0;
    _ghosts = [];
    int ghostIdx = 0;
    final ghostColors = [
      const Color(0xFFEF5350), // red
      const Color(0xFFF48FB1), // pink
      const Color(0xFF4DD0E1), // cyan
      const Color(0xFFFFA726), // orange
    ];

    _pac = _Actor(row: _rows - 3, col: _cols ~/ 2, dir: _Dir.left);

    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        final ch = maze[r][c];
        if (ch == '.' || ch == 'o') _dotsRemaining++;
        if (ch == 'P') _pac = _Actor(row: r, col: c, dir: _Dir.left);
        if (ch == 'G') {
          _ghosts.add(_Ghost(
            id: ghostIdx,
            color: ghostColors[ghostIdx % 4],
            row: r, col: c,
          ));
          ghostIdx++;
        }
      }
    }
    while (_ghosts.length < 2) {
      _ghosts.add(_Ghost(
        id: _ghosts.length,
        color: ghostColors[_ghosts.length % 4],
        row: _rows ~/ 2, col: _cols ~/ 2,
      ));
    }
    _initialDots = _dotsRemaining;
    _fruitPos = null;
    _fruitTicks = 0;
    _fruitSpawnedThisLevel = false;
  }

  Duration get _tickDuration {
    // Easy ramp: −8ms per wave, floor at 160ms — never frantic.
    final ms = (_baseTickMs - (_level - 1) * 8).clamp(160, _baseTickMs);
    return Duration(milliseconds: ms);
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickDuration, (_) => _tick());
    _mouthTimer?.cancel();
    _mouthTimer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (mounted) setState(() => _mouthOpen = !_mouthOpen);
    });
  }

  void _startGame() {
    _score = 0;
    _lives = 3;
    _level = 1;
    _gameOver = false;
    _won = false;
    _started = true;
    _frightTicks = 0;
    _ghostEatChain = 0;
    _pendingDir = _Dir.none;
    _resetMaze();
    _levelIntroTicks = 10; // short banner at start
    _restartTimer();
    setState(() {});
  }

  void _nextLevel() {
    _level++;
    _frightTicks = 0;
    _ghostEatChain = 0;
    _pendingDir = _Dir.none;
    _resetMaze();
    _levelIntroTicks = 12;
    _won = false;
    _restartTimer();
    setState(() {});
  }

  /// Pick a random empty path tile for the bonus fruit.
  void _spawnFruit() {
    _fruitSpawnedThisLevel = true;
    final rng = Random();
    final empties = <(int, int)>[];
    for (int r = 1; r < _rows - 1; r++) {
      for (int c = 1; c < _cols - 1; c++) {
        final ch = _tiles[r][c];
        if (ch == ' ' || ch == '.') {
          // Avoid spawning right on top of actors
          if (_pac.row == r && _pac.col == c) continue;
          if (_ghosts.any((g) => g.row == r && g.col == c)) continue;
          empties.add((r, c));
        }
      }
    }
    if (empties.isEmpty) return;
    _fruitPos = empties[rng.nextInt(empties.length)];
    _fruitTicks = 80; // ~16 seconds at 200ms ticks
    HapticFeedback.selectionClick();
  }

  void _resetPositionsAfterDeath() {
    _pendingDir = _Dir.none;
    _frightTicks = 0;
    _ghostEatChain = 0;
    // Reset pac and ghosts to spawn positions; keep dots state
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        if (_currentMaze[r][c] == 'P') {
          _pac = _Actor(row: r, col: c, dir: _Dir.left);
        }
      }
    }
    if (!_mazeHasPacSpawn()) {
      _pac = _Actor(row: _rows - 3, col: _cols ~/ 2, dir: _Dir.left);
    }
    for (final g in _ghosts) {
      g.row = g.spawnRow;
      g.col = g.spawnCol;
      g.dir = _Dir.up;
      g.frightened = false;
      g.eaten = false;
    }
  }

  bool _mazeHasPacSpawn() {
    for (final row in _currentMaze) {
      if (row.contains('P')) return true;
    }
    return false;
  }

  bool _isWall(int r, int c) {
    if (r < 0 || r >= _rows) return true;
    // Horizontal tunnel wrap: column out-of-range wraps
    if (c < 0 || c >= _cols) return false;
    return _tiles[r][c] == '#';
  }

  (int, int) _stepCoord(int r, int c, _Dir d) {
    switch (d) {
      case _Dir.up:    return (r - 1, c);
      case _Dir.down:  return (r + 1, c);
      case _Dir.left:  return (r, c - 1);
      case _Dir.right: return (r, c + 1);
      case _Dir.none:  return (r, c);
    }
  }

  (int, int) _wrap(int r, int c) {
    if (c < 0) c = _cols - 1;
    if (c >= _cols) c = 0;
    return (r, c);
  }

  void _tick() {
    if (_gameOver || _won) return;

    // Level intro pause — don't move pieces while the banner shows.
    if (_levelIntroTicks > 0) {
      _levelIntroTicks--;
      setState(() {});
      return;
    }

    // Move Pac-Man
    if (_pendingDir != _Dir.none) {
      final (tr, tc) = _stepCoord(_pac.row, _pac.col, _pendingDir);
      final (wr, wc) = _wrap(tr, tc);
      if (!_isWall(wr, wc)) {
        _pac.dir = _pendingDir;
        _pendingDir = _Dir.none;
      }
    }
    final (pr, pc) = _stepCoord(_pac.row, _pac.col, _pac.dir);
    final (wpr, wpc) = _wrap(pr, pc);
    if (!_isWall(wpr, wpc)) {
      _pac.row = wpr;
      _pac.col = wpc;
    }

    // Eat dot / pellet
    final t = _tiles[_pac.row][_pac.col];
    if (t == '.') {
      _tiles[_pac.row][_pac.col] = ' ';
      _score += 10;
      _dotsRemaining--;
      HapticFeedback.selectionClick();
    } else if (t == 'o') {
      _tiles[_pac.row][_pac.col] = ' ';
      _score += 50;
      _dotsRemaining--;
      // Longer fright on level 1 (70 ticks) and level 2 (60) to reward exploration.
      _frightTicks = (_level == 1 ? 70 : _level == 2 ? 60 : (55 - (_level - 3) * 5)).clamp(20, 70);
      _ghostEatChain = 0;
      for (final g in _ghosts) {
        if (!g.eaten) g.frightened = true;
      }
      HapticFeedback.mediumImpact();
    }

    // Bonus fruit: spawn once when half the dots are eaten.
    if (!_fruitSpawnedThisLevel &&
        _initialDots > 0 &&
        _dotsRemaining <= _initialDots ~/ 2) {
      _spawnFruit();
    }

    // Fruit collision / timeout
    if (_fruitPos != null) {
      if (_pac.row == _fruitPos!.$1 && _pac.col == _fruitPos!.$2) {
        _score += 100;
        _fruitPos = null;
        _fruitTicks = 0;
        HapticFeedback.mediumImpact();
      } else {
        _fruitTicks--;
        if (_fruitTicks <= 0) {
          _fruitPos = null;
        }
      }
    }

    // Move ghosts — slower on easy levels (level 1: 2 of 3 ticks, level 2: 4 of 5).
    _tickCounter++;
    bool moveGhostsThisTick = true;
    if (_level == 1 && _tickCounter % 3 == 0) moveGhostsThisTick = false;
    else if (_level == 2 && _tickCounter % 5 == 0) moveGhostsThisTick = false;

    if (moveGhostsThisTick) {
      for (final g in _ghosts) {
        _moveGhost(g);
      }
    }

    // Collision detection (post-move)
    _handleCollisions();

    // Decrement fright timer
    if (_frightTicks > 0) {
      _frightTicks--;
      if (_frightTicks == 0) {
        for (final g in _ghosts) { g.frightened = false; }
      }
    }

    // Check win
    if (_dotsRemaining <= 0) {
      _won = true;
      _timer?.cancel();
      _mouthTimer?.cancel();
      if (_score > _bestScore) { _bestScore = _score; _saveBest(); }
      HapticFeedback.heavyImpact();
      _promptHighScore();
    }

    setState(() {});
  }

  void _handleCollisions() {
    for (final g in _ghosts) {
      if (g.row == _pac.row && g.col == _pac.col) {
        if (g.eaten) continue;
        if (g.frightened) {
          _ghostEatChain++;
          _score += 200 * _ghostEatChain; // 200, 400, 800, 1600
          g.eaten = true;
          g.frightened = false;
          // Send back to spawn
          g.row = g.spawnRow; g.col = g.spawnCol;
          HapticFeedback.heavyImpact();
        } else {
          _lives--;
          HapticFeedback.heavyImpact();
          if (_lives <= 0) {
            _gameOver = true;
            _timer?.cancel();
            _mouthTimer?.cancel();
            if (_score > _bestScore) { _bestScore = _score; _saveBest(); }
            _promptHighScore();
          } else {
            _resetPositionsAfterDeath();
          }
          return;
        }
      }
    }
    // Clear eaten flag when ghost returns to spawn (already there)
    for (final g in _ghosts) {
      if (g.eaten && g.row == g.spawnRow && g.col == g.spawnCol) {
        // Respawn after a few ticks — simple: immediate
        g.eaten = false;
      }
    }
  }

  void _moveGhost(_Ghost g) {
    final options = <_Dir>[];
    final reverse = _reverse(g.dir);
    for (final d in [_Dir.up, _Dir.down, _Dir.left, _Dir.right]) {
      if (d == reverse) continue;
      final (nr, nc) = _stepCoord(g.row, g.col, d);
      final (wr, wc) = _wrap(nr, nc);
      if (!_isWall(wr, wc)) options.add(d);
    }

    // If stuck, allow reversing
    if (options.isEmpty) options.add(reverse);

    _Dir chosen;
    if (g.frightened) {
      chosen = options[Random().nextInt(options.length)];
    } else {
      // Pick direction closest to target (chase) or farthest (scatter per ghost)
      // Each ghost has a slight variation for flavor.
      final target = _ghostTarget(g);
      int bestScore = -1;
      chosen = options.first;
      for (final d in options) {
        final (nr, nc) = _stepCoord(g.row, g.col, d);
        final (wr, wc) = _wrap(nr, nc);
        final dist = (wr - target.$1).abs() + (wc - target.$2).abs();
        // Lower distance = better. Invert for comparison.
        final score = 1000 - dist;
        if (score > bestScore) { bestScore = score; chosen = d; }
      }
    }

    g.dir = chosen;
    final (nr, nc) = _stepCoord(g.row, g.col, g.dir);
    final (wr, wc) = _wrap(nr, nc);
    if (!_isWall(wr, wc)) {
      g.row = wr;
      g.col = wc;
    }
  }

  (int, int) _ghostTarget(_Ghost g) {
    switch (g.id % 4) {
      case 0: // red — direct chase
        return (_pac.row, _pac.col);
      case 1: // pink — 3 tiles ahead of pac
        final (tr, tc) = _stepCoord(_pac.row, _pac.col, _pac.dir);
        final (tr2, tc2) = _stepCoord(tr, tc, _pac.dir);
        return _stepCoord(tr2, tc2, _pac.dir);
      case 2: // cyan — mix (opposite of pink)
        return (_rows - 1 - _pac.row, _cols - 1 - _pac.col);
      default: // orange — chase if far, scatter corner if near
        final dist = (g.row - _pac.row).abs() + (g.col - _pac.col).abs();
        if (dist > 6) return (_pac.row, _pac.col);
        return (_rows - 1, 0);
    }
  }

  _Dir _reverse(_Dir d) {
    switch (d) {
      case _Dir.up:    return _Dir.down;
      case _Dir.down:  return _Dir.up;
      case _Dir.left:  return _Dir.right;
      case _Dir.right: return _Dir.left;
      case _Dir.none:  return _Dir.none;
    }
  }

  void _changeDirection(_Dir d) {
    _pendingDir = d;
    // If Pac currently isn't moving, apply immediately
    if (_pac.dir == _Dir.none) {
      final (nr, nc) = _stepCoord(_pac.row, _pac.col, d);
      final (wr, wc) = _wrap(nr, nc);
      if (!_isWall(wr, wc)) _pac.dir = d;
    }
    HapticFeedback.selectionClick();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  Widget _dpadButton(IconData icon, _Dir d) {
    return GestureDetector(
      onTap: () => _changeDirection(d),
      child: Container(
        width: 62, height: 62,
        decoration: BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GameTheme.border, width: 1.5),
        ),
        child: Icon(icon, color: GameTheme.accent, size: 38),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Pac-Man'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () { _timer?.cancel(); _mouthTimer?.cancel(); Navigator.pop(context); },
        ),
        actions: [
          IconButton(
            icon: Icon(_useDpad ? Icons.swipe_rounded : Icons.gamepad_rounded,
              color: GameTheme.accent),
            tooltip: _useDpad ? 'Switch to Swipe' : 'Switch to D-Pad',
            onPressed: () => setState(() => _useDpad = !_useDpad),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Pac-Man'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final dpadH = _useDpad ? 200.0 : 0.0;
          final availW = min(constraints.maxWidth - 16, 680.0);
          final availH = constraints.maxHeight - 80 - dpadH;
          final cellW = availW / _cols;
          final cellH = availH / _rows;
          final cellSize = min(cellW, cellH);
          final boardW = cellSize * _cols;
          final boardH = cellSize * _rows;

          return Column(children: [
            // HUD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat('SCORE', '$_score'),
                  _stat('LIVES', '$_lives'),
                  _stat('LEVEL', '$_level'),
                  _stat('BEST', '$_bestScore'),
                ],
              ),
            ),

            Expanded(child: Center(child: GestureDetector(
              onPanStart: (d) => _swipeStart = d.localPosition,
              onPanUpdate: (d) {
                if (_swipeStart == null) return;
                final delta = d.localPosition - _swipeStart!;
                if (delta.distance < 18) return;
                if (delta.dx.abs() > delta.dy.abs()) {
                  _changeDirection(delta.dx > 0 ? _Dir.right : _Dir.left);
                } else {
                  _changeDirection(delta.dy > 0 ? _Dir.down : _Dir.up);
                }
                _swipeStart = d.localPosition;
              },
              child: Container(
                width: boardW, height: boardH,
                decoration: BoxDecoration(
                  color: const Color(0xFF050812),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: GameTheme.border, width: 1.5),
                ),
                child: Stack(children: [
                  // Maze tiles (walls + dots)
                  for (int r = 0; r < _rows; r++)
                    for (int c = 0; c < _cols; c++)
                      _tileWidget(r, c, cellSize),

                  // Ghosts (animated for smooth glide between tiles)
                  for (int i = 0; i < _ghosts.length; i++)
                    AnimatedPositioned(
                      key: ValueKey('ghost-$i'),
                      duration: _tickDuration,
                      curve: Curves.linear,
                      left: _ghosts[i].col * cellSize,
                      top: _ghosts[i].row * cellSize,
                      width: cellSize, height: cellSize,
                      child: _ghostWidget(_ghosts[i], cellSize),
                    ),

                  // Pac-Man (animated for smooth glide between tiles)
                  AnimatedPositioned(
                    duration: _tickDuration,
                    curve: Curves.linear,
                    left: _pac.col * cellSize,
                    top: _pac.row * cellSize,
                    width: cellSize, height: cellSize,
                    child: _pacWidget(cellSize),
                  ),

                  // Bonus fruit
                  if (_fruitPos != null)
                    Positioned(
                      left: _fruitPos!.$2 * cellSize,
                      top: _fruitPos!.$1 * cellSize,
                      child: SizedBox(
                        width: cellSize, height: cellSize,
                        child: Center(child: Text('\u{1F352}',
                          style: TextStyle(fontSize: cellSize * 0.8))),
                      ),
                    ),

                  // Level intro banner
                  if (_levelIntroTicks > 0 && _started && !_gameOver)
                    Positioned.fill(child: Center(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: GameTheme.background.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Wave $_level',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                            color: GameTheme.accent)),
                        const SizedBox(height: 2),
                        Text(_currentMazeName,
                          style: const TextStyle(fontSize: 14, color: GameTheme.textSecondary)),
                      ]),
                    ))),

                  // Overlay: start / game-over / win
                  if (!_started || _gameOver || _won)
                    Positioned.fill(child: Center(child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: GameTheme.background.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          _won ? 'Cleared!' : _gameOver ? 'Game Over' : 'Pac-Man',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                            color: _won ? GameTheme.accent
                                : _gameOver ? GameTheme.accentAlt
                                : GameTheme.accent),
                        ),
                        if (_gameOver || _won) ...[
                          const SizedBox(height: 6),
                          Text('Score: $_score',
                            style: const TextStyle(color: GameTheme.textSecondary, fontSize: 14)),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _won ? _nextLevel : _startGame,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GameTheme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          ),
                          child: Text(
                            _won ? 'Next Wave' : _gameOver ? 'Play Again' : 'Start',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        if (!_started && !_gameOver) ...[
                          const SizedBox(height: 10),
                          Text(_useDpad ? 'Use D-Pad to move' : 'Swipe to change direction',
                            style: const TextStyle(color: GameTheme.textSecondary, fontSize: 12)),
                        ],
                      ]),
                    ))),
                ]),
              ),
            ))),

            // D-Pad
            if (_useDpad && _started && !_gameOver && !_won)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _dpadButton(Icons.arrow_drop_up_rounded, _Dir.up),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _dpadButton(Icons.arrow_left_rounded, _Dir.left),
                    const SizedBox(width: 62),
                    _dpadButton(Icons.arrow_right_rounded, _Dir.right),
                  ]),
                  _dpadButton(Icons.arrow_drop_down_rounded, _Dir.down),
                ]),
              )
            else
              const SizedBox(height: 8),
          ]);
        }),
      ),
    );
  }

  Widget _tileWidget(int r, int c, double size) {
    final ch = _tiles[r][c];
    Widget? inner;
    if (ch == '#') {
      inner = Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F3A8A),
          borderRadius: BorderRadius.circular(size * 0.2),
          boxShadow: [
            BoxShadow(color: const Color(0xFF3B5FE0).withValues(alpha: 0.3),
              blurRadius: 2, spreadRadius: -1),
          ],
        ),
      );
    } else if (ch == '.') {
      inner = Center(child: Container(
        width: size * 0.2, height: size * 0.2,
        decoration: const BoxDecoration(
          color: Color(0xFFF4D58D), shape: BoxShape.circle,
        ),
      ));
    } else if (ch == 'o') {
      inner = Center(child: Container(
        width: size * 0.55, height: size * 0.55,
        decoration: BoxDecoration(
          color: const Color(0xFFF4D58D), shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: const Color(0xFFF4D58D).withValues(alpha: 0.6),
              blurRadius: 4),
          ],
        ),
      ));
    }
    if (inner == null) return const SizedBox.shrink();
    return Positioned(
      left: c * size, top: r * size,
      width: size, height: size,
      child: Padding(
        padding: EdgeInsets.all(ch == '#' ? 0 : size * 0.1),
        child: inner,
      ),
    );
  }

  Widget _pacWidget(double size) {
    final padding = size * 0.08;
    final double angle;
    switch (_pac.dir) {
      case _Dir.up:    angle = -pi / 2; break;
      case _Dir.down:  angle = pi / 2; break;
      case _Dir.left:  angle = pi; break;
      case _Dir.right:
      case _Dir.none:  angle = 0;
    }
    return SizedBox(
      width: size, height: size,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Transform.rotate(
          angle: angle,
          child: CustomPaint(
            painter: _PacPainter(mouthOpen: _mouthOpen && _started && !_gameOver),
          ),
        ),
      ),
    );
  }

  Widget _ghostWidget(_Ghost g, double size) {
    Color c;
    if (g.eaten) {
      c = const Color(0xFFE0E0E0);
    } else if (g.frightened) {
      final blinking = _frightTicks > 0 && _frightTicks < 12 && _frightTicks.isEven;
      c = blinking ? const Color(0xFFF4F4F4) : const Color(0xFF4564FF);
    } else {
      c = g.color;
    }
    final padding = size * 0.1;
    return SizedBox(
      width: size, height: size,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: CustomPaint(
          painter: _GhostPainter(color: c, eaten: g.eaten, frightened: g.frightened),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: GameTheme.textSecondary, letterSpacing: 1.2)),
      const SizedBox(height: 2),
      Text(value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
          color: GameTheme.accent)),
    ]);
  }
}

class _PacPainter extends CustomPainter {
  final bool mouthOpen;
  _PacPainter({required this.mouthOpen});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final paint = Paint()..color = const Color(0xFFFFD54F);
    if (!mouthOpen) {
      canvas.drawCircle(center, r, paint);
      return;
    }
    final mouthAngle = 0.9;
    final start = mouthAngle / 2;
    final sweep = 2 * pi - mouthAngle;
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: r),
        start, sweep, false)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PacPainter old) => old.mouthOpen != mouthOpen;
}

class _GhostPainter extends CustomPainter {
  final Color color;
  final bool eaten;
  final bool frightened;
  _GhostPainter({required this.color, required this.eaten, required this.frightened});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = color;

    // Body: rounded top + wavy bottom
    final path = Path();
    path.moveTo(0, h);
    path.lineTo(0, h * 0.5);
    path.arcToPoint(Offset(w, h * 0.5),
      radius: Radius.circular(w / 2), clockwise: true);
    path.lineTo(w, h);
    // Wavy bottom
    const waves = 4;
    final waveW = w / waves;
    for (int i = waves; i > 0; i--) {
      final x = i * waveW;
      path.lineTo(x - waveW * 0.5, h * 0.85);
      path.lineTo(x - waveW, h);
    }
    path.close();
    canvas.drawPath(path, body);

    // Eyes — skip if eaten (just show eyes floating)
    final eyeWhite = Paint()..color = Colors.white;
    final pupil = Paint()..color = frightened ? const Color(0xFFFFE082) : const Color(0xFF1A237E);
    final eyeR = w * 0.14;
    final leftEye = Offset(w * 0.32, h * 0.42);
    final rightEye = Offset(w * 0.68, h * 0.42);

    if (eaten) {
      // Only eyes
      canvas.drawCircle(leftEye, eyeR, eyeWhite);
      canvas.drawCircle(rightEye, eyeR, eyeWhite);
      canvas.drawCircle(leftEye, eyeR * 0.45, pupil);
      canvas.drawCircle(rightEye, eyeR * 0.45, pupil);
      return;
    }

    if (frightened) {
      // Frightened expression: small circular eyes + zigzag mouth
      canvas.drawCircle(leftEye, eyeR * 0.7, pupil);
      canvas.drawCircle(rightEye, eyeR * 0.7, pupil);
      final mouthPaint = Paint()
        ..color = const Color(0xFFFFE082)
        ..strokeWidth = w * 0.05
        ..style = PaintingStyle.stroke;
      final mouthPath = Path();
      final my = h * 0.7;
      final mw = w * 0.55;
      final mx = (w - mw) / 2;
      const segments = 5;
      for (int i = 0; i <= segments; i++) {
        final px = mx + (mw / segments) * i;
        final py = my + (i.isOdd ? -w * 0.05 : w * 0.05);
        if (i == 0) { mouthPath.moveTo(px, py); }
        else { mouthPath.lineTo(px, py); }
      }
      canvas.drawPath(mouthPath, mouthPaint);
      return;
    }

    canvas.drawCircle(leftEye, eyeR, eyeWhite);
    canvas.drawCircle(rightEye, eyeR, eyeWhite);
    canvas.drawCircle(leftEye, eyeR * 0.45, pupil);
    canvas.drawCircle(rightEye, eyeR * 0.45, pupil);
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.color != color || old.eaten != eaten || old.frightened != frightened;
}
