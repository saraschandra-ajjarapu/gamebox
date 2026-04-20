import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';

enum SudokuMode { menu, playing }

class SudokuScreen extends StatefulWidget {
  const SudokuScreen({super.key});
  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends State<SudokuScreen>
    with TickerProviderStateMixin {
  SudokuMode _mode = SudokuMode.menu;
  late List<List<int>> _board;    // current state
  late List<List<int>> _solution; // full solution
  late List<List<bool>> _fixed;   // clue cells
  late List<List<Set<int>>> _notes; // pencil marks
  (int, int)? _selected;
  int _errors = 0;
  bool _gameOver = false;
  bool _won = false;
  bool _notesMode = false;
  int _difficulty = 30; // cells to remove
  String _diffLabel = 'Medium';
  final _rng = Random();
  Set<int> _completedBoxes = {}; // track which 3x3 boxes are complete

  Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _time = '0:00';

  // Box completion animation
  AnimationController? _boxAnimCtrl;
  int _animatingBox = -1;

  @override
  void dispose() { _timer?.cancel(); _boxAnimCtrl?.dispose(); super.dispose(); }

  void _generate() {
    _solution = List.generate(9, (_) => List.filled(9, 0));
    _fillGrid(_solution);
    _board = _solution.map((r) => [...r]).toList();
    _notes = List.generate(9, (_) => List.generate(9, (_) => <int>{}));
    _fixed = List.generate(9, (_) => List.filled(9, true));

    // Remove cells
    int removed = 0;
    final cells = List.generate(81, (i) => i)..shuffle(_rng);
    for (final idx in cells) {
      if (removed >= _difficulty) break;
      final r = idx ~/ 9, c = idx % 9;
      _board[r][c] = 0;
      _fixed[r][c] = false;
      removed++;
    }
  }

  bool _fillGrid(List<List<int>> grid) {
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        if (grid[r][c] != 0) continue;
        final nums = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(_rng);
        for (final n in nums) {
          if (_isValid(grid, r, c, n)) {
            grid[r][c] = n;
            if (_fillGrid(grid)) return true;
            grid[r][c] = 0;
          }
        }
        return false;
      }
    }
    return true;
  }

  bool _isValid(List<List<int>> grid, int r, int c, int n) {
    for (int i = 0; i < 9; i++) {
      if (grid[r][i] == n || grid[i][c] == n) return false;
    }
    final br = (r ~/ 3) * 3, bc = (c ~/ 3) * 3;
    for (int i = br; i < br + 3; i++) {
      for (int j = bc; j < bc + 3; j++) {
        if (grid[i][j] == n) return false;
      }
    }
    return true;
  }

  void _startGame(int diff, String label) {
    _difficulty = diff; _diffLabel = label;
    _generate();
    _selected = null; _errors = 0; _gameOver = false; _won = false;
    _notesMode = false; _completedBoxes = {};
    _stopwatch = Stopwatch()..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_gameOver) {
        final s = _stopwatch.elapsed.inSeconds;
        setState(() => _time = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}');
      }
    });
    _mode = SudokuMode.playing; setState(() {});
  }

  void _onCellTap(int r, int c) {
    if (_gameOver) return;
    _selected = (r, c);
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _checkBoxCompletion(int r, int c) {
    final boxR = (r ~/ 3) * 3, boxC = (c ~/ 3) * 3;
    final boxIndex = (r ~/ 3) * 3 + (c ~/ 3);
    if (_completedBoxes.contains(boxIndex)) return;

    bool boxComplete = true;
    for (int i = boxR; i < boxR + 3; i++) {
      for (int j = boxC; j < boxC + 3; j++) {
        if (_board[i][j] != _solution[i][j]) { boxComplete = false; break; }
      }
      if (!boxComplete) break;
    }
    if (boxComplete) {
      _completedBoxes.add(boxIndex);
      _animatingBox = boxIndex;
      _boxAnimCtrl?.dispose();
      _boxAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
      _boxAnimCtrl!.forward().then((_) {
        if (mounted) setState(() => _animatingBox = -1);
      });
      HapticFeedback.heavyImpact();
    }
  }

  void _onNumber(int n) {
    if (_selected == null || _gameOver) return;
    final (r, c) = _selected!;
    if (_fixed[r][c]) return;

    // Notes mode
    if (_notesMode && n != 0) {
      if (_notes[r][c].contains(n)) {
        _notes[r][c].remove(n);
      } else {
        _notes[r][c].add(n);
      }
      _board[r][c] = 0; // clear value when adding notes
      HapticFeedback.selectionClick();
      setState(() {});
      return;
    }

    if (n == 0) { _board[r][c] = 0; _notes[r][c].clear(); setState(() {}); return; }

    _board[r][c] = n;
    _notes[r][c].clear(); // clear notes when placing number
    if (n != _solution[r][c]) {
      _errors++;
      HapticFeedback.heavyImpact();
      if (_errors >= 3) { _gameOver = true; _stopwatch.stop(); }
    } else {
      HapticFeedback.lightImpact();
      _checkBoxCompletion(r, c);
      // Check win
      bool complete = true;
      for (int i = 0; i < 9; i++) {
        for (int j = 0; j < 9; j++) {
          if (_board[i][j] != _solution[i][j]) complete = false;
        }
      }
      if (complete) { _won = true; _gameOver = true; _stopwatch.stop(); HapticFeedback.heavyImpact(); }
    }
    setState(() {});
  }

  void _hint() {
    if (_gameOver) return;
    // Find an empty or wrong cell and fill it
    final cells = <(int, int)>[];
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        if (!_fixed[r][c] && _board[r][c] != _solution[r][c]) cells.add((r, c));
      }
    }
    if (cells.isEmpty) return;
    final (r, c) = cells[_rng.nextInt(cells.length)];
    _board[r][c] = _solution[r][c];
    _selected = (r, c);
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == SudokuMode.menu) return _buildMenu();
    return _buildGame();
  }

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(title: const Text('Sudoku'), leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
        onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Sudoku'),
          ),
        ]),
      body: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔢', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 8),
          const Text('Sudoku', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
          const SizedBox(height: 36),
          _diffBtn('Easy', 'More clues', () => _startGame(25, 'Easy')),
          const SizedBox(height: 12),
          _diffBtn('Medium', 'Balanced', () => _startGame(35, 'Medium')),
          const SizedBox(height: 12),
          _diffBtn('Hard', 'Fewer clues', () => _startGame(45, 'Hard')),
        ]))));
  }

  Widget _diffBtn(String label, String sub, VoidCallback onTap) {
    return GestureDetector(onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(color: GameTheme.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border)),
        child: Row(children: [
          const Icon(Icons.grid_on_rounded, color: GameTheme.accent, size: 24), const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
            Text(sub, style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary))]),
          const Spacer(), const Icon(Icons.arrow_forward_ios_rounded, color: GameTheme.textSecondary, size: 16)])));
  }

  Widget _buildGame() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(title: Text('Sudoku — $_diffLabel'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () { _timer?.cancel(); setState(() => _mode = SudokuMode.menu); }),
        actions: [
          IconButton(icon: const Icon(Icons.lightbulb_outline_rounded, color: GameTheme.gold), onPressed: _hint, tooltip: 'Hint'),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
            onPressed: () => _startGame(_difficulty, _diffLabel))]),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final gridSize = min(constraints.maxWidth - 16, constraints.maxHeight - 220);
        final cellSize = gridSize / 9;

        return Column(children: [
          // Stats
          Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              Text('⏱️ $_time', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GameTheme.textPrimary)),
              Text('❌ $_errors/3', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: _errors >= 2 ? GameTheme.accentAlt : GameTheme.textPrimary))])),

          const SizedBox(height: 4),

          // Grid
          Center(child: Container(
            width: gridSize, height: gridSize,
            decoration: BoxDecoration(border: Border.all(color: GameTheme.accent, width: 2), borderRadius: BorderRadius.circular(4)),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(), itemCount: 81,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 9),
              itemBuilder: (_, i) {
                final r = i ~/ 9, c = i % 9;
                return _buildCell(r, c, cellSize);
              }))),

          if (_gameOver) Padding(padding: const EdgeInsets.only(top: 12),
            child: Column(children: [
              Text(_won ? '🎉 Solved!' : '💔 Game Over',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                  color: _won ? GameTheme.accent : GameTheme.accentAlt)),
              if (_won) Text('Time: $_time', style: const TextStyle(fontSize: 14, color: GameTheme.textSecondary)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => _startGame(_difficulty, _diffLabel),
                style: ElevatedButton.styleFrom(backgroundColor: GameTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('New Puzzle', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)))])),

          const Spacer(),

          // Notes toggle + Number pad
          if (!_gameOver) ...[
            // Notes toggle
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: GestureDetector(
                onTap: () { setState(() => _notesMode = !_notesMode); HapticFeedback.selectionClick(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _notesMode ? GameTheme.accent.withValues(alpha: 0.2) : GameTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _notesMode ? GameTheme.accent : GameTheme.border, width: _notesMode ? 2 : 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_note_rounded, size: 18,
                      color: _notesMode ? GameTheme.accent : GameTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(_notesMode ? 'Notes ON' : 'Notes',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: _notesMode ? GameTheme.accent : GameTheme.textSecondary))])))),

            Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  ...List.generate(9, (i) => Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _numBtn(i + 1)))),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _numBtn(0, icon: Icons.backspace_outlined))),
                ])),
          ],

          const SizedBox(height: 12),
        ]);
      })),
    );
  }

  Widget _buildCell(int r, int c, double size) {
    final val = _board[r][c];
    final isFixed = _fixed[r][c];
    final isSelected = _selected == (r, c);
    final selectedVal = _selected != null ? _board[_selected!.$1][_selected!.$2] : 0;
    final isSameNum = val != 0 && selectedVal == val && !isSelected;
    final isSameRow = _selected != null && _selected!.$1 == r;
    final isSameCol = _selected != null && _selected!.$2 == c;
    final isSameBox = _selected != null &&
        (r ~/ 3) == (_selected!.$1 ~/ 3) && (c ~/ 3) == (_selected!.$2 ~/ 3);
    final isError = val != 0 && !isFixed && val != _solution[r][c];
    final boxIndex = (r ~/ 3) * 3 + (c ~/ 3);
    final isBoxAnimating = _animatingBox == boxIndex;
    final cellNotes = _notes[r][c];

    final rightThick = (c + 1) % 3 == 0 && c < 8;
    final bottomThick = (r + 1) % 3 == 0 && r < 8;

    Color bg;
    if (isSelected) {
      bg = GameTheme.accent.withValues(alpha: 0.35);
    } else if (isSameNum) {
      bg = GameTheme.accent.withValues(alpha: 0.22);
    } else if (isSameRow || isSameCol || isSameBox) {
      bg = GameTheme.accent.withValues(alpha: 0.08);
    } else {
      bg = GameTheme.surface;
    }

    // Box completion glow
    if (isBoxAnimating && _boxAnimCtrl != null) {
      final t = _boxAnimCtrl!.value;
      bg = Color.lerp(bg, GameTheme.accent.withValues(alpha: 0.3), (1 - t) * 0.5)!;
    }

    Widget content;
    if (val != 0) {
      content = Text('$val', style: TextStyle(
        fontSize: size * 0.5,
        fontWeight: isFixed ? FontWeight.w800 : FontWeight.w500,
        color: isError ? GameTheme.accentAlt : isFixed ? GameTheme.textPrimary : GameTheme.accent));
    } else if (cellNotes.isNotEmpty) {
      // Show notes as small numbers in a 3x3 grid
      content = Padding(padding: const EdgeInsets.all(1),
        child: GridView.count(
          crossAxisCount: 3, physics: const NeverScrollableScrollPhysics(),
          children: List.generate(9, (i) {
            final n = i + 1;
            return Center(child: Text(
              cellNotes.contains(n) ? '$n' : '',
              style: TextStyle(fontSize: size * 0.16, color: GameTheme.textSecondary,
                fontWeight: FontWeight.w500)));
          })));
    } else {
      content = const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _onCellTap(r, c),
      child: isBoxAnimating && _boxAnimCtrl != null
        ? AnimatedBuilder(animation: _boxAnimCtrl!, builder: (_, __) => Container(
            decoration: BoxDecoration(color: bg,
              border: Border(
                right: BorderSide(color: rightThick ? GameTheme.accent : GameTheme.border, width: rightThick ? 2 : 0.5),
                bottom: BorderSide(color: bottomThick ? GameTheme.accent : GameTheme.border, width: bottomThick ? 2 : 0.5))),
            child: Center(child: content)))
        : Container(
            decoration: BoxDecoration(color: bg,
              border: Border(
                right: BorderSide(color: rightThick ? GameTheme.accent : GameTheme.border, width: rightThick ? 2 : 0.5),
                bottom: BorderSide(color: bottomThick ? GameTheme.accent : GameTheme.border, width: bottomThick ? 2 : 0.5))),
            child: Center(child: content)));
  }

  Widget _numBtn(int n, {IconData? icon}) {
    return GestureDetector(
      onTap: () => _onNumber(n),
      child: Container(height: 44,
        decoration: BoxDecoration(color: GameTheme.surface, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GameTheme.border)),
        child: Center(child: icon != null
          ? Icon(icon, color: GameTheme.textSecondary, size: 18)
          : Text('$n', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)))));
  }
}
