import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';

class SnakeGameScreen extends StatefulWidget {
  const SnakeGameScreen({super.key});

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

enum Direction { up, down, left, right }

// Special food types that appear randomly during gameplay
enum FoodType {
  normal,      // Regular food — always present
  fake,        // Vanishes when snake gets within 3 cells
  rockOrReal,  // Two foods appear — one real, one rock
  timed,       // Bonus food — disappears after 30 seconds
}

class _SnakeGameScreenState extends State<SnakeGameScreen> {
  static const int _baseTickMs = 220; // starting speed

  int _rows = 20;
  int _cols = 20;
  List<(int, int)> _snake = [];
  (int, int) _food = (0, 0);
  Direction _direction = Direction.right;
  Direction _nextDirection = Direction.right;
  Timer? _timer;
  int _score = 0;
  int _bestScore = 0;
  bool _gameOver = false;
  bool _started = false;
  final _random = Random();

  // Special food system
  FoodType? _specialFoodType;
  (int, int)? _specialFood;       // Special food position
  (int, int)? _rockFood;          // Rock position (for rockOrReal)
  bool _isSpecialReal = true;     // Which one is real in rock/real pair
  Timer? _specialTimer;
  Timer? _timedFoodTimer;
  int _timedFoodSeconds = 0;
  bool _headShaking = false;      // Snake shakes head on rock
  int _specialCooldown = 0;       // Ticks before next special can spawn

  // Controls
  bool _useDpad = false; // false = swipe, true = d-pad
  Offset? _swipeStart;

  @override
  void initState() {
    super.initState();
    _loadBestScore();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _bestScore = prefs.getInt('best_score_snake') ?? 0);
  }

  Future<void> _saveBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score_snake', _bestScore);
  }

  Duration get _currentTick {
    // Gentle speed increase every 50 points — relaxed pacing
    final speedLevel = _score ~/ 50;
    final ms = (_baseTickMs - speedLevel * 8).clamp(120, _baseTickMs);
    return Duration(milliseconds: ms);
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_currentTick, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _specialTimer?.cancel();
    _timedFoodTimer?.cancel();
    super.dispose();
  }

  void _startGame() {
    _snake = [(_rows ~/ 2, _cols ~/ 2), (_rows ~/ 2, _cols ~/ 2 - 1), (_rows ~/ 2, _cols ~/ 2 - 2)];
    _direction = Direction.right;
    _nextDirection = Direction.right;
    _score = 0;
    _gameOver = false;
    _started = true;
    _specialFoodType = null;
    _specialFood = null;
    _rockFood = null;
    _headShaking = false;
    _specialCooldown = 0;
    _specialTimer?.cancel();
    _timedFoodTimer?.cancel();
    _placeFood();
    _restartTimer();
    setState(() {});
  }

  (int, int) _randomFreeCell() {
    while (true) {
      final r = _random.nextInt(_rows);
      final c = _random.nextInt(_cols);
      if (!_snake.contains((r, c)) && (r, c) != _food &&
          (r, c) != _specialFood && (r, c) != _rockFood) {
        return (r, c);
      }
    }
  }

  void _placeFood() {
    _food = _randomFreeCell();
  }

  void _trySpawnSpecialFood() {
    if (_specialFoodType != null || _specialCooldown > 0) return;

    // 15% chance each normal food eat after score >= 30
    if (_score < 30 || _random.nextInt(100) >= 15) return;

    final type = FoodType.values[_random.nextInt(3) + 1]; // fake, rockOrReal, timed
    _specialFoodType = type;
    _specialCooldown = 40; // Minimum ticks before next special

    switch (type) {
      case FoodType.fake:
        _specialFood = _randomFreeCell();
        // Auto-expire after 10 seconds
        _specialTimer?.cancel();
        _specialTimer = Timer(const Duration(seconds: 10), () {
          if (mounted) setState(() => _clearSpecial());
        });
        break;

      case FoodType.rockOrReal:
        _specialFood = _randomFreeCell();
        _rockFood = _randomFreeCell();
        _isSpecialReal = _random.nextBool();
        // Auto-expire after 8 seconds
        _specialTimer?.cancel();
        _specialTimer = Timer(const Duration(seconds: 8), () {
          if (mounted) setState(() => _clearSpecial());
        });
        break;

      case FoodType.timed:
        _specialFood = _randomFreeCell();
        _timedFoodSeconds = 30;
        _timedFoodTimer?.cancel();
        _timedFoodTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) { t.cancel(); return; }
          setState(() {
            _timedFoodSeconds--;
            if (_timedFoodSeconds <= 0) {
              t.cancel();
              _clearSpecial();
            }
          });
        });
        break;

      default:
        break;
    }
  }

  void _clearSpecial() {
    _specialFoodType = null;
    _specialFood = null;
    _rockFood = null;
    _specialTimer?.cancel();
    _timedFoodTimer?.cancel();
  }

  void _tick() {
    if (_gameOver) return;

    _direction = _nextDirection;
    final (hr, hc) = _snake.first;

    late (int, int) newHead;
    switch (_direction) {
      case Direction.up:    newHead = (hr - 1, hc);
      case Direction.down:  newHead = (hr + 1, hc);
      case Direction.left:  newHead = (hr, hc - 1);
      case Direction.right: newHead = (hr, hc + 1);
    }

    // Wall wrap-around
    final nr = (newHead.$1 + _rows) % _rows;
    final nc = (newHead.$2 + _cols) % _cols;
    newHead = (nr, nc);

    // Self collision
    if (_snake.contains(newHead)) {
      _endGame();
      return;
    }

    _snake.insert(0, newHead);

    bool ateFood = false;

    // Eat normal food
    if (newHead == _food) {
      _score += 10;
      HapticFeedback.mediumImpact();
      _placeFood();
      ateFood = true;
      if (_score % 50 == 0) _restartTimer();
      _trySpawnSpecialFood();
    }

    // Check special food interactions
    if (_specialFoodType != null) {
      switch (_specialFoodType!) {
        case FoodType.fake:
          // Fake food vanishes when snake gets within 3 cells
          if (_specialFood != null) {
            final dist = (newHead.$1 - _specialFood!.$1).abs() +
                (newHead.$2 - _specialFood!.$2).abs();
            if (dist <= 3) {
              setState(() => _clearSpecial());
            }
          }
          break;

        case FoodType.rockOrReal:
          if (newHead == _specialFood || newHead == _rockFood) {
            final ateSpecial = newHead == _specialFood;
            final ateRealOne = (ateSpecial && _isSpecialReal) ||
                (!ateSpecial && !_isSpecialReal);

            if (ateRealOne) {
              // Ate the real one — bonus!
              _score += 20;
              HapticFeedback.mediumImpact();
              ateFood = true;
            } else {
              // Ate the rock — head shake, no death
              _headShaking = true;
              HapticFeedback.heavyImpact();
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setState(() => _headShaking = false);
              });
            }
            _clearSpecial();
          }
          break;

        case FoodType.timed:
          if (newHead == _specialFood) {
            // Bonus points based on time remaining
            final bonus = 15 + _timedFoodSeconds;
            _score += bonus;
            HapticFeedback.mediumImpact();
            ateFood = true;
            _clearSpecial();
          }
          break;

        default:
          break;
      }
    }

    if (!ateFood) {
      _snake.removeLast();
    }

    if (_specialCooldown > 0) _specialCooldown--;

    setState(() {});
  }

  void _endGame() {
    _timer?.cancel();
    _specialTimer?.cancel();
    _timedFoodTimer?.cancel();
    _gameOver = true;
    if (_score > _bestScore) { _bestScore = _score; _saveBestScore(); }
    HapticFeedback.heavyImpact();
    setState(() {});
  }

  void _changeDirection(Direction newDir) {
    if (_direction == Direction.up && newDir == Direction.down) return;
    if (_direction == Direction.down && newDir == Direction.up) return;
    if (_direction == Direction.left && newDir == Direction.right) return;
    if (_direction == Direction.right && newDir == Direction.left) return;
    _nextDirection = newDir;
  }

  Widget _dpadButton(IconData icon, Direction dir) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _changeDirection(dir);
      },
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GameTheme.border),
        ),
        child: Icon(icon, color: GameTheme.accent, size: 32),
      ),
    );
  }

  Widget _buildFoodWidget((int, int) pos, double cellSize, Color color, String emoji) {
    return Positioned(
      left: pos.$2 * cellSize + 1,
      top: pos.$1 * cellSize + 1,
      child: Container(
        width: cellSize - 2,
        height: cellSize - 2,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(cellSize / 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
          ],
        ),
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: cellSize * 0.6)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Snake'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () {
            _timer?.cancel();
            Navigator.pop(context);
          },
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
            onPressed: () => GameHelp.show(context, 'Snake'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate grid to fill available space
            final availW = constraints.maxWidth - 24; // 12px padding each side
            final dpadHeight = _useDpad ? 160.0 : 0.0;
            final availH = constraints.maxHeight - 80 - dpadHeight; // score bar + dpad + padding

            // Determine cell size and grid dimensions
            final maxCellSize = 22.0; // cap cell size for phones
            final minCellSize = 14.0; // min for iPads with many cells

            // Calculate how many cells fit
            double cellSize;
            if (availW / 20 > maxCellSize) {
              // iPad or large screen — use more cells
              cellSize = max(minCellSize, min(maxCellSize, availW / 25));
              _cols = (availW / cellSize).floor();
              _rows = (availH / cellSize).floor();
            } else {
              // iPhone — use available width
              cellSize = availW / 20;
              _cols = 20;
              _rows = (availH / cellSize).floor();
            }

            // Clamp grid size
            _cols = _cols.clamp(12, 40);
            _rows = _rows.clamp(16, 50);

            final gridW = _cols * cellSize;
            final gridH = _rows * cellSize;

            return Column(
              children: [
                // Score bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Score: $_score  ',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                              color: GameTheme.accent)),
                      Text('Best: $_bestScore',
                          style: const TextStyle(fontSize: 14, color: GameTheme.textSecondary)),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Game grid — fills available space
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onPanStart: (d) => _swipeStart = d.localPosition,
                      onPanUpdate: (d) {
                        if (_swipeStart == null) return;
                        final delta = d.localPosition - _swipeStart!;
                        if (delta.distance < 15) return;

                        if (delta.dx.abs() > delta.dy.abs()) {
                          _changeDirection(delta.dx > 0 ? Direction.right : Direction.left);
                        } else {
                          _changeDirection(delta.dy > 0 ? Direction.down : Direction.up);
                        }
                        _swipeStart = d.localPosition;
                      },
                      child: Container(
                        width: gridW,
                        height: gridH,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A1520),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: GameTheme.border, width: 1.5),
                        ),
                        child: Stack(
                          children: [
                            // Grid lines
                            CustomPaint(
                              size: Size(gridW, gridH),
                              painter: _GridPainter(cellSize: cellSize, cols: _cols, rows: _rows),
                            ),

                            // Normal food
                            _buildFoodWidget(_food, cellSize, GameTheme.accentAlt, '\u{1F34E}'),

                            // Special foods
                            if (_specialFoodType == FoodType.fake && _specialFood != null)
                              _buildFoodWidget(_specialFood!, cellSize,
                                const Color(0xFFFF9800), '\u{1F34A}'), // Orange — looks tempting

                            if (_specialFoodType == FoodType.rockOrReal) ...[
                              if (_specialFood != null)
                                _buildFoodWidget(_specialFood!, cellSize,
                                  const Color(0xFF66BB6A), _isSpecialReal ? '\u{1F34F}' : '\u{1FAA8}'),
                              if (_rockFood != null)
                                _buildFoodWidget(_rockFood!, cellSize,
                                  const Color(0xFF66BB6A), !_isSpecialReal ? '\u{1F34F}' : '\u{1FAA8}'),
                            ],

                            if (_specialFoodType == FoodType.timed && _specialFood != null) ...[
                              _buildFoodWidget(_specialFood!, cellSize,
                                const Color(0xFFFFD700), '\u{2B50}'),
                              // Timer badge
                              Positioned(
                                left: _specialFood!.$2 * cellSize - 4,
                                top: _specialFood!.$1 * cellSize - 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _timedFoodSeconds <= 10
                                      ? const Color(0xFFEF5350) : const Color(0xFF333333),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('${_timedFoodSeconds}s',
                                    style: const TextStyle(fontSize: 8,
                                      fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              ),
                            ],

                            // Snake body
                            for (int i = _snake.length - 1; i >= 1; i--)
                              Positioned(
                                left: _snake[i].$2 * cellSize + 2,
                                top: _snake[i].$1 * cellSize + 2,
                                child: Container(
                                  width: cellSize - 4 - (i / _snake.length) * 4,
                                  height: cellSize - 4 - (i / _snake.length) * 4,
                                  margin: EdgeInsets.all((i / _snake.length) * 2),
                                  decoration: BoxDecoration(
                                    color: Color.lerp(
                                      const Color(0xFF4ECDC4),
                                      const Color(0xFF2A9D8F),
                                      i / _snake.length,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      i == _snake.length - 1 ? cellSize : 5,
                                    ),
                                  ),
                                ),
                              ),

                            // Snake head
                            if (_snake.isNotEmpty)
                              Positioned(
                                left: _snake[0].$2 * cellSize + (_headShaking ? (_random.nextDouble() * 4 - 2) : 0),
                                top: _snake[0].$1 * cellSize + (_headShaking ? (_random.nextDouble() * 4 - 2) : 0),
                                child: SizedBox(
                                  width: cellSize,
                                  height: cellSize,
                                  child: CustomPaint(
                                    painter: _SnakeHeadPainter(
                                      direction: _started ? _direction : Direction.right,
                                      color: _headShaking
                                        ? const Color(0xFFEF5350)
                                        : const Color(0xFF4ECDC4),
                                    ),
                                  ),
                                ),
                              ),

                            // Start / Game Over overlay
                            if (!_started || _gameOver)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(30),
                                  decoration: BoxDecoration(
                                    color: GameTheme.background.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _gameOver ? 'Game Over' : 'Snake',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w800,
                                          color: _gameOver ? GameTheme.accentAlt : GameTheme.accent,
                                        ),
                                      ),
                                      if (_gameOver) ...[
                                        const SizedBox(height: 8),
                                        Text('Score: $_score',
                                            style: const TextStyle(color: GameTheme.textSecondary, fontSize: 16)),
                                      ],
                                      const SizedBox(height: 20),
                                      ElevatedButton(
                                        onPressed: _startGame,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: GameTheme.accent,
                                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: Text(
                                          _gameOver ? 'Play Again' : 'Start Game',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700, color: Colors.white),
                                        ),
                                      ),
                                      if (!_gameOver) ...[
                                        const SizedBox(height: 12),
                                        Text(_useDpad ? 'Use D-Pad to control' : 'Swipe to control',
                                            style: const TextStyle(color: GameTheme.textSecondary, fontSize: 13)),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // D-Pad controls
                if (_useDpad && _started && !_gameOver)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: 150,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dpadButton(Icons.arrow_drop_up_rounded, Direction.up),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _dpadButton(Icons.arrow_left_rounded, Direction.left),
                              const SizedBox(width: 48),
                              _dpadButton(Icons.arrow_right_rounded, Direction.right),
                            ],
                          ),
                          _dpadButton(Icons.arrow_drop_down_rounded, Direction.down),
                        ],
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SnakeHeadPainter extends CustomPainter {
  final Direction direction;
  final Color color;
  _SnakeHeadPainter({required this.direction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    switch (direction) {
      case Direction.up:    canvas.rotate(-pi / 2);
      case Direction.down:  canvas.rotate(pi / 2);
      case Direction.left:  canvas.rotate(pi);
      case Direction.right: break;
    }
    canvas.translate(-center.dx, -center.dy);

    // Head shape
    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.05, s * 0.1, s * 0.90, s * 0.80),
      Radius.circular(s * 0.35),
    );
    canvas.drawRRect(headRect, Paint()..color = color);

    // Snout
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.55, s * 0.18, s * 0.38, s * 0.64),
        Radius.circular(s * 0.30),
      ),
      Paint()..color = Color.lerp(color, Colors.white, 0.15)!,
    );

    // Eyes
    final eyeR = s * 0.10;
    canvas.drawCircle(Offset(s * 0.55, s * 0.30), eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(s * 0.58, s * 0.30), eyeR * 0.55, Paint()..color = const Color(0xFF1A1A2E));
    canvas.drawCircle(Offset(s * 0.60, s * 0.28), eyeR * 0.2, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(s * 0.55, s * 0.70), eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(s * 0.58, s * 0.70), eyeR * 0.55, Paint()..color = const Color(0xFF1A1A2E));
    canvas.drawCircle(Offset(s * 0.60, s * 0.68), eyeR * 0.2, Paint()..color = Colors.white);

    // Tongue
    final tonguePaint = Paint()
      ..color = const Color(0xFFFF4444)
      ..strokeWidth = s * 0.04
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.92, s * 0.50), Offset(s * 1.05, s * 0.50), tonguePaint);
    canvas.drawLine(Offset(s * 1.05, s * 0.50), Offset(s * 1.10, s * 0.42), tonguePaint..strokeWidth = s * 0.025);
    canvas.drawLine(Offset(s * 1.05, s * 0.50), Offset(s * 1.10, s * 0.58), tonguePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SnakeHeadPainter old) => old.direction != direction;
}

class _GridPainter extends CustomPainter {
  final double cellSize;
  final int cols;
  final int rows;
  _GridPainter({required this.cellSize, required this.cols, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0E1E2E)
      ..strokeWidth = 0.5;

    for (int i = 1; i < cols; i++) {
      canvas.drawLine(Offset(i * cellSize, 0), Offset(i * cellSize, size.height), paint);
    }
    for (int i = 1; i < rows; i++) {
      canvas.drawLine(Offset(0, i * cellSize), Offset(size.width, i * cellSize), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
