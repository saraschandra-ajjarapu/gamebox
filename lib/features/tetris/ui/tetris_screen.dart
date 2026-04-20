import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/widgets/high_score_dialog.dart';

class TetrisScreen extends StatefulWidget {
  const TetrisScreen({super.key});

  @override
  State<TetrisScreen> createState() => _TetrisScreenState();
}

// Tetromino shapes — each list is one rotation state, encoded as 4×4 cell occupancy
// (1 = filled, 0 = empty). Pieces rotate by cycling the list.
class _Piece {
  final int typeIndex;
  final List<List<List<int>>> rotations;
  int rotation = 0;
  int row;
  int col;

  _Piece(this.typeIndex, this.rotations, {required this.row, required this.col});

  List<List<int>> get shape => rotations[rotation % rotations.length];
  int get colorIndex => typeIndex + 1; // board cells store color index; 0 = empty
}

// 7 classic tetromino shapes.
const _tetrominoRotations = <List<List<List<int>>>>[
  // I
  [
    [[0,0,0,0],[1,1,1,1],[0,0,0,0],[0,0,0,0]],
    [[0,0,1,0],[0,0,1,0],[0,0,1,0],[0,0,1,0]],
  ],
  // O
  [
    [[0,1,1,0],[0,1,1,0],[0,0,0,0],[0,0,0,0]],
  ],
  // T
  [
    [[0,1,0,0],[1,1,1,0],[0,0,0,0],[0,0,0,0]],
    [[0,1,0,0],[0,1,1,0],[0,1,0,0],[0,0,0,0]],
    [[0,0,0,0],[1,1,1,0],[0,1,0,0],[0,0,0,0]],
    [[0,1,0,0],[1,1,0,0],[0,1,0,0],[0,0,0,0]],
  ],
  // S
  [
    [[0,1,1,0],[1,1,0,0],[0,0,0,0],[0,0,0,0]],
    [[1,0,0,0],[1,1,0,0],[0,1,0,0],[0,0,0,0]],
  ],
  // Z
  [
    [[1,1,0,0],[0,1,1,0],[0,0,0,0],[0,0,0,0]],
    [[0,1,0,0],[1,1,0,0],[1,0,0,0],[0,0,0,0]],
  ],
  // J
  [
    [[1,0,0,0],[1,1,1,0],[0,0,0,0],[0,0,0,0]],
    [[0,1,1,0],[0,1,0,0],[0,1,0,0],[0,0,0,0]],
    [[0,0,0,0],[1,1,1,0],[0,0,1,0],[0,0,0,0]],
    [[0,1,0,0],[0,1,0,0],[1,1,0,0],[0,0,0,0]],
  ],
  // L
  [
    [[0,0,1,0],[1,1,1,0],[0,0,0,0],[0,0,0,0]],
    [[0,1,0,0],[0,1,0,0],[0,1,1,0],[0,0,0,0]],
    [[0,0,0,0],[1,1,1,0],[1,0,0,0],[0,0,0,0]],
    [[1,1,0,0],[0,1,0,0],[0,1,0,0],[0,0,0,0]],
  ],
];

// Muted, low-saturation palette — flat fills, easy on the eyes.
const _pieceColors = <Color>[
  Color(0xFF6FA8A8), // I — dusty teal
  Color(0xFFD4B06A), // O — muted gold
  Color(0xFF9B85B8), // T — grey-lavender
  Color(0xFF7AAE89), // S — muted sage
  Color(0xFFC47878), // Z — terracotta
  Color(0xFF7A95BA), // J — slate blue
  Color(0xFFC99870), // L — tan
];

class _TetrisScreenState extends State<TetrisScreen> {
  static const int _rows = 20;
  static const int _cols = 10;
  static const int _baseTickMs = 780;

  late List<List<int>> _board;
  _Piece? _current;
  _Piece? _next;
  final _rng = Random();

  int _score = 0;
  int _bestScore = 0;
  int _level = 1;
  int _linesCleared = 0;
  bool _gameOver = false;
  bool _started = false;
  bool _paused = false;
  Timer? _timer;

  bool _useDpad = false;
  Offset? _swipeStart;

  @override
  void initState() {
    super.initState();
    _board = List.generate(_rows, (_) => List.filled(_cols, 0));
    _loadBest();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _bestScore = prefs.getInt('best_score_tetris') ?? 0);
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score_tetris', _bestScore);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration get _tickDuration {
    // Gentle ramp: drop 30ms per level, floor at 180ms so it never becomes frantic.
    final ms = (_baseTickMs - (_level - 1) * 30).clamp(180, _baseTickMs);
    return Duration(milliseconds: ms);
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickDuration, (_) => _tick());
  }

  _Piece _spawn() {
    final typeIndex = _rng.nextInt(_tetrominoRotations.length);
    return _Piece(typeIndex, _tetrominoRotations[typeIndex], row: 0, col: 3);
  }

  void _startGame() {
    _board = List.generate(_rows, (_) => List.filled(_cols, 0));
    _score = 0;
    _level = 1;
    _linesCleared = 0;
    _gameOver = false;
    _started = true;
    _paused = false;
    _current = _spawn();
    _next = _spawn();
    _restartTimer();
    setState(() {});
  }

  void _togglePause() {
    if (!_started || _gameOver) return;
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _timer?.cancel();
      } else {
        _restartTimer();
      }
    });
  }

  bool _collides(_Piece piece, {int? r, int? c, int? rot}) {
    final shape = piece.rotations[(rot ?? piece.rotation) % piece.rotations.length];
    final baseR = r ?? piece.row;
    final baseC = c ?? piece.col;
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (shape[i][j] == 0) continue;
        final nr = baseR + i;
        final nc = baseC + j;
        if (nc < 0 || nc >= _cols || nr >= _rows) return true;
        if (nr < 0) continue; // above top is fine
        if (_board[nr][nc] != 0) return true;
      }
    }
    return false;
  }

  void _lockPiece() {
    final p = _current!;
    final shape = p.shape;
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (shape[i][j] == 0) continue;
        final nr = p.row + i;
        final nc = p.col + j;
        if (nr >= 0 && nr < _rows && nc >= 0 && nc < _cols) {
          _board[nr][nc] = p.colorIndex;
        }
      }
    }
    _clearLines();
    _current = _next;
    _next = _spawn();
    if (_current != null && _collides(_current!)) {
      _endGame();
    }
  }

  void _clearLines() {
    int cleared = 0;
    for (int r = _rows - 1; r >= 0; r--) {
      if (_board[r].every((v) => v != 0)) {
        _board.removeAt(r);
        _board.insert(0, List.filled(_cols, 0));
        cleared++;
        r++; // recheck same index (now holds row above)
      }
    }
    if (cleared > 0) {
      HapticFeedback.mediumImpact();
      const points = [0, 40, 100, 300, 1200];
      _score += points[cleared] * _level;
      _linesCleared += cleared;
      final newLevel = 1 + _linesCleared ~/ 10;
      if (newLevel != _level) {
        _level = newLevel;
        _restartTimer();
      }
    }
  }

  void _tick() {
    if (_paused || _gameOver || _current == null) return;
    final p = _current!;
    if (!_collides(p, r: p.row + 1)) {
      setState(() => p.row += 1);
    } else {
      setState(_lockPiece);
    }
  }

  void _moveH(int delta) {
    if (!_started || _paused || _gameOver || _current == null) return;
    final p = _current!;
    if (!_collides(p, c: p.col + delta)) {
      HapticFeedback.selectionClick();
      setState(() => p.col += delta);
    }
  }

  void _softDrop() {
    if (!_started || _paused || _gameOver || _current == null) return;
    final p = _current!;
    if (!_collides(p, r: p.row + 1)) {
      setState(() {
        p.row += 1;
        _score += 1;
      });
    }
  }

  void _hardDrop() {
    if (!_started || _paused || _gameOver || _current == null) return;
    final p = _current!;
    int dist = 0;
    while (!_collides(p, r: p.row + dist + 1)) {
      dist++;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      p.row += dist;
      _score += dist * 2;
      _lockPiece();
    });
  }

  void _rotate() {
    if (!_started || _paused || _gameOver || _current == null) return;
    final p = _current!;
    final nextRot = (p.rotation + 1) % p.rotations.length;
    // Basic wall kick — try shifts
    const kicks = [0, -1, 1, -2, 2];
    for (final k in kicks) {
      if (!_collides(p, c: p.col + k, rot: nextRot)) {
        HapticFeedback.selectionClick();
        setState(() {
          p.rotation = nextRot;
          p.col += k;
        });
        return;
      }
    }
  }

  void _endGame() {
    _timer?.cancel();
    _gameOver = true;
    if (_score > _bestScore) {
      _bestScore = _score;
      _saveBest();
    }
    HapticFeedback.heavyImpact();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HighScoreDialog.submitIfQualifies(
        context: context, gameId: 'tetris', gameName: 'Tetris', score: _score);
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  Color _colorFor(int cell) {
    if (cell == 0) return Colors.transparent;
    return _pieceColors[cell - 1];
  }

  Widget _cell(Color color, double size, {bool ghost = false}) {
    if (color == Colors.transparent) {
      return Container(width: size, height: size, margin: const EdgeInsets.all(0.5));
    }
    if (ghost) {
      return Container(
        width: size, height: size,
        margin: const EdgeInsets.all(0.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.1),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
        ),
      );
    }
    // Subtle bevel: brighter top-left → color → slightly darker bottom-right,
    // plus a thin darker border so adjacent same-color cells stay distinct.
    final light = Color.lerp(color, Colors.white, 0.18)!;
    final shade = Color.lerp(color, Colors.black, 0.22)!;
    final border = Color.lerp(color, Colors.black, 0.35)!;
    return Container(
      width: size, height: size,
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [light, color, shade],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(size * 0.1),
        border: Border.all(color: border, width: 0.8),
      ),
    );
  }

  // Ghost projection — where the current piece would land.
  int _ghostRow(_Piece p) {
    int d = 0;
    while (!_collides(p, r: p.row + d + 1)) {
      d++;
    }
    return p.row + d;
  }

  Widget _dpadButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62, height: 62,
        decoration: BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GameTheme.border, width: 1.5),
        ),
        child: Icon(icon, color: GameTheme.accent, size: 36),
      ),
    );
  }

  Widget _previewPiece(_Piece? p) {
    if (p == null) return const SizedBox.shrink();
    final shape = p.shape;
    int minR = 4, maxR = -1, minC = 4, maxC = -1;
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (shape[i][j] != 0) {
          minR = min(minR, i); maxR = max(maxR, i);
          minC = min(minC, j); maxC = max(maxC, j);
        }
      }
    }
    if (maxR < 0) return const SizedBox.shrink();
    final h = maxR - minR + 1;
    final w = maxC - minC + 1;
    const cell = 14.0;
    final color = _pieceColors[p.typeIndex];
    // FittedBox scales the preview down to fit any container; inline cells
    // (no margins) so the child's intrinsic size matches the SizedBox exactly.
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: w * cell,
        height: h * cell,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(h, (i) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(w, (j) {
              final filled = shape[minR + i][minC + j] != 0;
              return Container(
                width: cell, height: cell,
                decoration: BoxDecoration(
                  color: filled ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Tetris'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () { _timer?.cancel(); Navigator.pop(context); },
        ),
        actions: [
          IconButton(
            icon: Icon(_useDpad ? Icons.swipe_rounded : Icons.gamepad_rounded,
              color: GameTheme.accent),
            tooltip: _useDpad ? 'Switch to Swipe' : 'Switch to D-Pad',
            onPressed: () => setState(() => _useDpad = !_useDpad),
          ),
          if (_started && !_gameOver)
            IconButton(
              icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: GameTheme.accent),
              onPressed: _togglePause,
            ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Tetris'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final dpadH = _useDpad ? 88.0 : 0.0;
          final availH = constraints.maxHeight - dpadH - 56;
          // Use ~70% of width on tablets so the board is big without stretching absurdly.
          final totalAvailW = constraints.maxWidth - 24;
          final availW = min(totalAvailW, 640.0);
          final previewReserve = availW >= 260 ? 80.0 : 0.0;
          final boardAvailW = availW - previewReserve;
          final cellByW = boardAvailW / _cols;
          final cellByH = availH / _rows;
          final cellSize = min(cellByW, cellByH);
          final boardW = cellSize * _cols;
          final boardH = cellSize * _rows;

          return Column(children: [
            // Score bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statBox('SCORE', '$_score'),
                  _statBox('LINES', '$_linesCleared'),
                  _statBox('LEVEL', '$_level'),
                  _statBox('BEST', '$_bestScore'),
                ],
              ),
            ),

            // Board + next-piece preview
            Expanded(child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _rotate,
                    onPanStart: (d) => _swipeStart = d.localPosition,
                    onPanUpdate: (d) {
                      if (_swipeStart == null) return;
                      final delta = d.localPosition - _swipeStart!;
                      if (delta.distance < 18) return;
                      if (delta.dx.abs() > delta.dy.abs()) {
                        _moveH(delta.dx > 0 ? 1 : -1);
                      } else {
                        if (delta.dy > 0) {
                          _softDrop();
                        } else {
                          _hardDrop();
                        }
                      }
                      _swipeStart = d.localPosition;
                    },
                    child: Container(
                      width: boardW, height: boardH,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1420),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: GameTheme.border, width: 1.5),
                      ),
                      child: Stack(children: [
                        // Board cells
                        for (int r = 0; r < _rows; r++)
                          for (int c = 0; c < _cols; c++)
                            if (_board[r][c] != 0)
                              Positioned(
                                left: c * cellSize,
                                top: r * cellSize,
                                child: _cell(_colorFor(_board[r][c]), cellSize),
                              ),
                        // Ghost (landing preview)
                        if (_current != null && _started && !_gameOver)
                          ..._pieceCells(_current!, cellSize,
                            rowOverride: _ghostRow(_current!), ghost: true),
                        // Current piece
                        if (_current != null && _started && !_gameOver)
                          ..._pieceCells(_current!, cellSize),

                        // Start / game-over overlay
                        if (!_started || _gameOver || _paused)
                          Positioned.fill(child: Center(child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: GameTheme.background.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                _gameOver ? 'Game Over' : _paused ? 'Paused' : 'Tetris',
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                                  color: _gameOver ? GameTheme.accentAlt : GameTheme.accent),
                              ),
                              if (_gameOver) ...[
                                const SizedBox(height: 6),
                                Text('Score: $_score',
                                  style: const TextStyle(color: GameTheme.textSecondary, fontSize: 14)),
                              ],
                              const SizedBox(height: 16),
                              if (!_paused)
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
                                )
                              else
                                ElevatedButton(
                                  onPressed: _togglePause,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: GameTheme.accent,
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                                  ),
                                  child: const Text('Resume',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              if (!_started && !_gameOver) ...[
                                const SizedBox(height: 10),
                                Text(_useDpad ? 'Use D-Pad to control' : 'Swipe to move · tap to rotate',
                                  style: const TextStyle(color: GameTheme.textSecondary, fontSize: 12)),
                              ],
                            ]),
                          ))),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Next-piece sidebar
                  if (previewReserve > 0)
                    SizedBox(
                      width: 72,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('NEXT',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: GameTheme.textSecondary, letterSpacing: 1.5)),
                          const SizedBox(height: 8),
                          Container(
                            width: 72, height: 72,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: GameTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(child: _previewPiece(_next)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            )),

            // D-Pad controls
            if (_useDpad && _started && !_gameOver && !_paused)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _dpadButton(Icons.rotate_right_rounded, _rotate),
                    _dpadButton(Icons.arrow_left_rounded, () => _moveH(-1)),
                    _dpadButton(Icons.arrow_drop_down_rounded, _softDrop),
                    _dpadButton(Icons.arrow_right_rounded, () => _moveH(1)),
                    _dpadButton(Icons.vertical_align_bottom_rounded, _hardDrop),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),
          ]);
        }),
      ),
    );
  }

  List<Widget> _pieceCells(_Piece p, double cellSize,
      {int? rowOverride, bool ghost = false}) {
    final widgets = <Widget>[];
    final shape = p.shape;
    final baseR = rowOverride ?? p.row;
    final color = _pieceColors[p.typeIndex];
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (shape[i][j] == 0) continue;
        final nr = baseR + i;
        final nc = p.col + j;
        if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols) continue;
        widgets.add(Positioned(
          left: nc * cellSize,
          top: nr * cellSize,
          child: _cell(color, cellSize, ghost: ghost),
        ));
      }
    }
    return widgets;
  }

  Widget _statBox(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: GameTheme.textSecondary, letterSpacing: 1.2)),
        const SizedBox(height: 2),
        Text(value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
            color: GameTheme.accent)),
      ],
    );
  }
}
