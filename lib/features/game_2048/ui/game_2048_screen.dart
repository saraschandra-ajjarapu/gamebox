import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';

// ── Seasonal themes ───────────────────────────────────────────────────────

class TileTheme {
  final String name;
  final String emoji;
  final Color gridBg;
  final Color cellBg;
  final Map<int, Color> tileColors;
  final Color lowTextColor;
  final Color highTextColor;

  const TileTheme({
    required this.name,
    required this.emoji,
    required this.gridBg,
    required this.cellBg,
    required this.tileColors,
    required this.lowTextColor,
    required this.highTextColor,
  });
}

final _themes = [
  // Classic (default)
  TileTheme(
    name: 'Classic',
    emoji: '🎲',
    gridBg: const Color(0xFF1E3040),
    cellBg: const Color(0xFF162530),
    lowTextColor: const Color(0xFF776E65),
    highTextColor: Colors.white,
    tileColors: {
      2: const Color(0xFFEEE4DA), 4: const Color(0xFFEDE0C8),
      8: const Color(0xFFF2B179), 16: const Color(0xFFF59563),
      32: const Color(0xFFF67C5F), 64: const Color(0xFFF65E3B),
      128: const Color(0xFFEDCF72), 256: const Color(0xFFEDCC61),
      512: const Color(0xFFEDC850), 1024: const Color(0xFFEDC53F),
      2048: const Color(0xFFEDC22E),
    },
  ),

  // Fall / Autumn
  TileTheme(
    name: 'Autumn',
    emoji: '🍂',
    gridBg: const Color(0xFF2D1B0E),
    cellBg: const Color(0xFF1F1208),
    lowTextColor: const Color(0xFF5C3D1E),
    highTextColor: const Color(0xFFFFF8E7),
    tileColors: {
      2: const Color(0xFFF5DEB3), 4: const Color(0xFFDEB887),
      8: const Color(0xFFD2691E), 16: const Color(0xFFCC5500),
      32: const Color(0xFFB8450E), 64: const Color(0xFF8B2500),
      128: const Color(0xFFCD853F), 256: const Color(0xFFDAA520),
      512: const Color(0xFFB8860B), 1024: const Color(0xFF8B6914),
      2048: const Color(0xFFFF8C00),
    },
  ),

  // Winter / Ice
  TileTheme(
    name: 'Winter',
    emoji: '❄️',
    gridBg: const Color(0xFF1A2A3A),
    cellBg: const Color(0xFF0F1E2E),
    lowTextColor: const Color(0xFF4A6B8A),
    highTextColor: Colors.white,
    tileColors: {
      2: const Color(0xFFE8F4F8), 4: const Color(0xFFD0E8F0),
      8: const Color(0xFF87CEEB), 16: const Color(0xFF5BA3CF),
      32: const Color(0xFF4682B4), 64: const Color(0xFF2E6DA0),
      128: const Color(0xFFB0C4DE), 256: const Color(0xFF8AADCC),
      512: const Color(0xFF6495ED), 1024: const Color(0xFF4169E1),
      2048: const Color(0xFF00BFFF),
    },
  ),

  // Spring / Bloom
  TileTheme(
    name: 'Spring',
    emoji: '🌸',
    gridBg: const Color(0xFF1A2E1A),
    cellBg: const Color(0xFF0F200F),
    lowTextColor: const Color(0xFF3D6B3D),
    highTextColor: Colors.white,
    tileColors: {
      2: const Color(0xFFE8F5E9), 4: const Color(0xFFC8E6C9),
      8: const Color(0xFF81C784), 16: const Color(0xFFFF9EB5),
      32: const Color(0xFFFF6F91), 64: const Color(0xFFE84580),
      128: const Color(0xFFFFEB3B), 256: const Color(0xFFFF9800),
      512: const Color(0xFF66BB6A), 1024: const Color(0xFF43A047),
      2048: const Color(0xFFE91E63),
    },
  ),

  // Christmas
  TileTheme(
    name: 'Christmas',
    emoji: '🎄',
    gridBg: const Color(0xFF1B0A0A),
    cellBg: const Color(0xFF120505),
    lowTextColor: const Color(0xFF5C2020),
    highTextColor: const Color(0xFFFFF8E7),
    tileColors: {
      2: const Color(0xFFF5E6E6), 4: const Color(0xFFE8C8C8),
      8: const Color(0xFFC62828), 16: const Color(0xFFAD1616),
      32: const Color(0xFF2E7D32), 64: const Color(0xFF1B5E20),
      128: const Color(0xFFFFD700), 256: const Color(0xFFFFC107),
      512: const Color(0xFFB71C1C), 1024: const Color(0xFF1B5E20),
      2048: const Color(0xFFFFD700),
    },
  ),

  // Halloween
  TileTheme(
    name: 'Halloween',
    emoji: '🎃',
    gridBg: const Color(0xFF1A0A1A),
    cellBg: const Color(0xFF0F050F),
    lowTextColor: const Color(0xFF6B3D6B),
    highTextColor: const Color(0xFFFFF8E7),
    tileColors: {
      2: const Color(0xFFE8D5F0), 4: const Color(0xFFD4A8E0),
      8: const Color(0xFFFF8C00), 16: const Color(0xFFFF6600),
      32: const Color(0xFF8B008B), 64: const Color(0xFF6A0DAD),
      128: const Color(0xFFFF4500), 256: const Color(0xFFCC3700),
      512: const Color(0xFF4B0082), 1024: const Color(0xFF2E0854),
      2048: const Color(0xFFFF6600),
    },
  ),
];

// ── Game screen ───────────────────────────────────────────────────────────

class Game2048Screen extends StatefulWidget {
  const Game2048Screen({super.key});

  @override
  State<Game2048Screen> createState() => _Game2048ScreenState();
}

class _Game2048ScreenState extends State<Game2048Screen>
    with TickerProviderStateMixin {
  static const int gridSize = 4;
  late List<List<int>> _grid;
  int _score = 0;
  int _bestScore = 0;
  bool _gameOver = false;
  bool _won = false;
  int _themeIndex = 0;
  final _random = Random();

  TileTheme get _theme => _themes[_themeIndex];

  @override
  void initState() {
    super.initState();
    _loadBestScore();
    _startNewGame();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _bestScore = prefs.getInt('best_score_2048') ?? 0);
  }

  Future<void> _saveBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score_2048', _bestScore);
  }

  void _startNewGame() {
    _grid = List.generate(gridSize, (_) => List.filled(gridSize, 0));
    _score = 0;
    _gameOver = false;
    _won = false;
    _addRandomTile();
    _addRandomTile();
    setState(() {});
  }

  void _addRandomTile() {
    final empty = <(int, int)>[];
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (_grid[r][c] == 0) empty.add((r, c));
      }
    }
    if (empty.isEmpty) return;
    final (r, c) = empty[_random.nextInt(empty.length)];
    _grid[r][c] = _random.nextDouble() < 0.9 ? 2 : 4;
  }

  List<int> _slideRow(List<int> row) {
    final tiles = row.where((v) => v != 0).toList();
    final result = <int>[];
    int i = 0;
    while (i < tiles.length) {
      if (i + 1 < tiles.length && tiles[i] == tiles[i + 1]) {
        final merged = tiles[i] * 2;
        result.add(merged);
        _score += merged;
        if (merged == 2048 && !_won) _won = true;
        i += 2;
      } else {
        result.add(tiles[i]);
        i++;
      }
    }
    while (result.length < gridSize) {
      result.add(0);
    }
    return result;
  }

  bool _move(int dr, int dc) {
    bool moved = false;
    final oldGrid = _grid.map((r) => [...r]).toList();

    if (dc != 0) {
      for (int r = 0; r < gridSize; r++) {
        var row = _grid[r].toList();
        if (dc > 0) row = row.reversed.toList();
        row = _slideRow(row);
        if (dc > 0) row = row.reversed.toList();
        _grid[r] = row;
      }
    } else {
      for (int c = 0; c < gridSize; c++) {
        var col = List.generate(gridSize, (r) => _grid[r][c]);
        if (dr > 0) col = col.reversed.toList();
        col = _slideRow(col);
        if (dr > 0) col = col.reversed.toList();
        for (int r = 0; r < gridSize; r++) {
          _grid[r][c] = col[r];
        }
      }
    }

    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (_grid[r][c] != oldGrid[r][c]) moved = true;
      }
    }

    if (moved) {
      _addRandomTile();
      if (_score > _bestScore) { _bestScore = _score; _saveBestScore(); }
      _checkGameOver();
    }

    return moved;
  }

  void _checkGameOver() {
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (_grid[r][c] == 0) return;
        if (c < gridSize - 1 && _grid[r][c] == _grid[r][c + 1]) return;
        if (r < gridSize - 1 && _grid[r][c] == _grid[r + 1][c]) return;
      }
    }
    _gameOver = true;
  }

  Offset? _dragStart;

  void _onPanStart(DragStartDetails details) {
    _dragStart = details.localPosition;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_gameOver || _dragStart == null) return;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_gameOver || _dragStart == null) return;

    final delta = details.localPosition - _dragStart!;
    const threshold = 20.0;
    if (delta.distance < threshold) return;

    bool moved;
    if (delta.dx.abs() > delta.dy.abs()) {
      moved = _move(0, delta.dx > 0 ? 1 : -1);
    } else {
      moved = _move(delta.dy > 0 ? 1 : -1, 0);
    }

    _dragStart = null;
    if (moved) HapticFeedback.lightImpact();
    setState(() {});
  }

  Color _tileColor(int v) {
    return _theme.tileColors[v] ?? const Color(0xFF3C3A32);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final gridW = screenW - 40;
    final tileSize = (gridW - 5 * 8) / 4;

    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('2048'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, '2048'),
          ),
          // Theme switcher
          IconButton(
            icon: const Icon(Icons.palette_outlined, color: GameTheme.textSecondary),
            onPressed: () => _showThemePicker(),
            tooltip: 'Change theme',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
            onPressed: _startNewGame,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),

          // Score bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _ScoreBox(label: 'SCORE', value: _score),
                const SizedBox(width: 12),
                _ScoreBox(label: 'BEST', value: _bestScore),
              ],
            ),
          ),

          // Theme indicator
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${_theme.emoji} ${_theme.name}',
              style: const TextStyle(fontSize: 13, color: GameTheme.textSecondary),
            ),
          ),

          const Spacer(),

          // Game grid
          GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Container(
              width: gridW,
              height: gridW,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _theme.gridBg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Empty cell backgrounds
                  for (int r = 0; r < gridSize; r++)
                    for (int c = 0; c < gridSize; c++)
                      Positioned(
                        left: c * (tileSize + 8),
                        top: r * (tileSize + 8),
                        child: Container(
                          width: tileSize,
                          height: tileSize,
                          decoration: BoxDecoration(
                            color: _theme.cellBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),

                  // Tiles
                  for (int r = 0; r < gridSize; r++)
                    for (int c = 0; c < gridSize; c++)
                      if (_grid[r][c] != 0)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          left: c * (tileSize + 8),
                          top: r * (tileSize + 8),
                          child: _buildTile(_grid[r][c], tileSize),
                        ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Swipe to move tiles',
            style: TextStyle(
              color: GameTheme.textSecondary.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),

          const Spacer(),

          // Game over / won
          if (_gameOver || _won)
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                children: [
                  Text(
                    _won ? 'You Win!' : 'Game Over',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: _won ? GameTheme.gold : GameTheme.accentAlt,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Score: $_score',
                      style: const TextStyle(color: GameTheme.textSecondary, fontSize: 16)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _startNewGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GameTheme.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Play Again',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTile(int value, double size) {
    final color = _tileColor(value);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: value >= 128
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12)]
            : null,
      ),
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: value < 100 ? 32 : value < 1000 ? 26 : 20,
                fontWeight: FontWeight.w800,
                color: value <= 4 ? _theme.lowTextColor : _theme.highTextColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: GameTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: GameTheme.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Choose Theme',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                    color: GameTheme.textPrimary)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(_themes.length, (i) => _themeOption(i)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(int index) {
    final t = _themes[index];
    final selected = _themeIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _themeIndex = index);
        Navigator.pop(context);
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? GameTheme.accent.withValues(alpha: 0.15) : GameTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? GameTheme.accent : GameTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(t.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(t.name,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: selected ? GameTheme.accent : GameTheme.textSecondary,
                )),
            const SizedBox(height: 6),
            // Mini color preview
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [2, 8, 32, 128].map((v) => Container(
                width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: t.tileColors[v],
                  borderRadius: BorderRadius.circular(3),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  final String label;
  final int value;
  const _ScoreBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GameTheme.border),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: GameTheme.textSecondary, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text('$value', style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}
