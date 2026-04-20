import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/widgets/high_score_dialog.dart';

class StackGameScreen extends StatefulWidget {
  const StackGameScreen({super.key});

  @override
  State<StackGameScreen> createState() => _StackGameScreenState();
}

class _Block {
  double x;      // left edge in table units [0, 1]
  double width;  // in table units
  _Block({required this.x, required this.width});
}

class _StackGameScreenState extends State<StackGameScreen>
    with SingleTickerProviderStateMixin {
  // All horizontal measurements in "table units" where 1.0 = full board width.
  static const double _blockHeightPx = 44.0;       // chunkier tiers
  static const double _blockTopDepthPx = 12.0;     // pseudo-3D top face
  static const double _initialWidth = 0.42;        // narrower to start
  static const double _perfectTolerance = 0.006;
  static const double _baseSpeed = 0.42;           // slower base pace

  final List<_Block> _stack = [];
  _Block _current = _Block(x: 0.24, width: _initialWidth);
  double _currentX = 0.24;
  double _direction = 1;
  double _speed = _baseSpeed;

  int _bestScore = 0;
  bool _started = false;
  bool _gameOver = false;
  bool _showPerfect = false;
  int _perfectStreak = 0;

  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadBest();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _bestScore = prefs.getInt('best_score_stack') ?? 0);
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score_stack', _bestScore);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  int get _score => _stack.isEmpty ? 0 : _stack.length - 1;

  void _startGame() {
    _stack.clear();
    // The foundation block sits perfectly centered; players must align to this.
    final foundation = _Block(x: (1 - _initialWidth) / 2, width: _initialWidth);
    _stack.add(foundation);
    _current = _Block(x: 0, width: _initialWidth);
    _currentX = 0;
    _direction = 1;
    _speed = _baseSpeed;
    _perfectStreak = 0;
    _gameOver = false;
    _started = true;
    _lastTickTime = Duration.zero;
    _ticker?.start();
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (!_started || _gameOver) return;
    if (_lastTickTime == Duration.zero) {
      _lastTickTime = elapsed;
      return;
    }
    final dt = ((elapsed - _lastTickTime).inMicroseconds / 1000000.0).clamp(0.0, 1 / 30);
    _lastTickTime = elapsed;

    _currentX += _direction * _speed * dt;
    final maxX = 1 - _current.width;
    if (_currentX < 0) {
      _currentX = 0;
      _direction = 1;
    } else if (_currentX > maxX) {
      _currentX = maxX;
      _direction = -1;
    }
    setState(() {});
  }

  void _drop() {
    if (!_started || _gameOver) return;
    final prev = _stack.last;
    final leftEdge = max(_currentX, prev.x);
    final rightEdge = min(_currentX + _current.width, prev.x + prev.width);
    final overlap = rightEdge - leftEdge;

    if (overlap <= 0) {
      // Missed entirely → game over
      HapticFeedback.heavyImpact();
      _gameOver = true;
      _ticker?.stop();
      if (_score > _bestScore) { _bestScore = _score; _saveBest(); }
      setState(() {});
      final finalScore = _score;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HighScoreDialog.submitIfQualifies(
          context: context, gameId: 'stack', gameName: 'Stack',
          score: finalScore, scoreLabel: 'Height');
      });
      return;
    }

    final offset = (_currentX - prev.x).abs();
    final isPerfect = offset < _perfectTolerance;
    final placed = isPerfect
        ? _Block(x: prev.x, width: prev.width) // keep full width
        : _Block(x: leftEdge, width: overlap);
    _stack.add(placed);

    if (isPerfect) {
      _perfectStreak++;
      _showPerfect = true;
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _showPerfect = false);
      });
    } else {
      _perfectStreak = 0;
      HapticFeedback.lightImpact();
    }

    // Spawn next sliding block with same width as placed block.
    _current = _Block(x: 0, width: placed.width);
    // Start from the side opposite to current direction for a rhythm.
    _currentX = _direction > 0 ? 1 - placed.width : 0;
    _direction = -_direction;

    // Speed ramps very slowly: +1.2% per block placed, capped low for calm play.
    _speed = (_baseSpeed * (1 + _stack.length * 0.012)).clamp(_baseSpeed, 0.95);

    setState(() {});
  }

  Color _blockColor(int index, int total) {
    // Hue cycles through a soothing gradient — blues → teals → greens → yellows → orange → pink → purple.
    final hue = (210 + index * 8) % 360.0;
    return HSVColor.fromAHSV(1.0, hue.toDouble(), 0.35, 0.85).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Stack'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () { _ticker?.stop(); Navigator.pop(context); },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Stack'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // Play area fills the screen on tablets; phones stay portrait-tight.
          final boardW = min(constraints.maxWidth - 24, 600.0);
          final boardH = constraints.maxHeight - 60;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat('SCORE', '$_score'),
                  if (_perfectStreak > 1)
                    _stat('STREAK', '$_perfectStreak', color: const Color(0xFFFFD54F)),
                  _stat('BEST', '$_bestScore'),
                ],
              ),
            ),
            Expanded(child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _started && !_gameOver ? _drop : null,
                child: SizedBox(
                  width: boardW, height: boardH,
                  child: Stack(children: [
                    // Background grid line
                    Positioned.fill(child: CustomPaint(
                      painter: _TowerPainter(
                        stack: _stack,
                        current: _current,
                        currentX: _currentX,
                        boardW: boardW,
                        boardH: boardH,
                        blockHeight: _blockHeightPx,
                        topDepth: _blockTopDepthPx,
                        colorFn: _blockColor,
                        started: _started,
                        gameOver: _gameOver,
                      ),
                    )),

                    if (_showPerfect)
                      Center(child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Text('PERFECT!',
                          style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900,
                            color: const Color(0xFFFFD54F),
                            letterSpacing: 2,
                            shadows: [Shadow(color: const Color(0xFFFFD54F).withValues(alpha: 0.6), blurRadius: 12)],
                          )),
                      )),

                    if (!_started || _gameOver)
                      Positioned.fill(child: Center(child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: GameTheme.background.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            _gameOver ? 'Game Over' : 'Stack',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                              color: _gameOver ? GameTheme.accentAlt : GameTheme.accent),
                          ),
                          if (_gameOver) ...[
                            const SizedBox(height: 6),
                            Text('Height: $_score',
                              style: const TextStyle(color: GameTheme.textSecondary, fontSize: 14)),
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _startGame,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: GameTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                            ),
                            child: Text(
                              _gameOver ? 'Play Again' : 'Start',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                          if (!_started && !_gameOver) ...[
                            const SizedBox(height: 10),
                            const Text('Tap anywhere to drop the block',
                              style: TextStyle(color: GameTheme.textSecondary, fontSize: 12)),
                          ],
                        ]),
                      ))),
                  ]),
                ),
              ),
            )),
          ]);
        }),
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: GameTheme.textSecondary, letterSpacing: 1.2)),
      const SizedBox(height: 2),
      Text(value,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
          color: color ?? GameTheme.accent)),
    ]);
  }
}

class _TowerPainter extends CustomPainter {
  final List<_Block> stack;
  final _Block current;
  final double currentX;
  final double boardW;
  final double boardH;
  final double blockHeight;
  final double topDepth;
  final Color Function(int index, int total) colorFn;
  final bool started;
  final bool gameOver;

  _TowerPainter({
    required this.stack,
    required this.current,
    required this.currentX,
    required this.boardW,
    required this.boardH,
    required this.blockHeight,
    required this.topDepth,
    required this.colorFn,
    required this.started,
    required this.gameOver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Soft night-sky background.
    final bgPaint = Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [const Color(0xFF0E1726), const Color(0xFF050A14)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final total = stack.length;
    // Foundation sits near the bottom; camera rises once tower crosses threshold.
    final bottomY = size.height - 90;
    const topAnchorY = 140.0;
    final naturalTopY = bottomY - (total - 1) * blockHeight;
    final cameraOffset = naturalTopY < topAnchorY ? (topAnchorY - naturalTopY) : 0.0;

    for (int i = 0; i < total; i++) {
      final block = stack[i];
      final y = bottomY - i * blockHeight + cameraOffset;
      if (y > size.height + blockHeight || y < -blockHeight * 2) continue;
      final rect = Rect.fromLTWH(
        block.x * size.width, y,
        block.width * size.width, blockHeight,
      );
      _drawBlock(canvas, rect, colorFn(i, total));
    }

    // Current sliding block above last placed block.
    if (started && !gameOver) {
      final y = bottomY - total * blockHeight + cameraOffset;
      final rect = Rect.fromLTWH(
        currentX * size.width, y,
        current.width * size.width, blockHeight,
      );
      _drawBlock(canvas, rect, colorFn(total, total + 1), glow: true);
    }
  }

  void _drawBlock(Canvas canvas, Rect rect, Color color, {bool glow = false}) {
    // Pseudo-3D: parallelogram top face + front rectangle.
    // Top face skews up and to the right so it reads as isometric-ish.
    final depth = topDepth;
    final color2 = Color.lerp(color, Colors.black, 0.35)!;
    final colorTop = Color.lerp(color, Colors.white, 0.15)!;

    // Front face
    final front = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    if (glow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(7)),
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawRRect(front, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color, color2],
    ).createShader(rect));

    // Top face as a parallelogram (slight right/up offset)
    final topPath = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.left + depth * 0.5, rect.top - depth)
      ..lineTo(rect.right + depth * 0.5, rect.top - depth)
      ..lineTo(rect.right, rect.top)
      ..close();
    canvas.drawPath(topPath, Paint()..color = colorTop);

    // Right face (a thin parallelogram)
    final rightPath = Path()
      ..moveTo(rect.right, rect.top)
      ..lineTo(rect.right + depth * 0.5, rect.top - depth)
      ..lineTo(rect.right + depth * 0.5, rect.bottom - depth)
      ..lineTo(rect.right, rect.bottom)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = Color.lerp(color, Colors.black, 0.12)!);

    // Subtle darker outline on the front
    canvas.drawRRect(front, Paint()
      ..color = Color.lerp(color, Colors.black, 0.4)!.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8);
  }

  @override
  bool shouldRepaint(_TowerPainter old) =>
      old.stack.length != stack.length ||
      old.currentX != currentX ||
      old.started != started || old.gameOver != gameOver;
}
