import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/services/wifi_game_service.dart';
import '../../../core/widgets/wifi_lobby.dart';

enum C4Mode { menu, playing }
enum C4Disc { none, red, yellow }

class Connect4Screen extends StatefulWidget {
  const Connect4Screen({super.key});
  @override
  State<Connect4Screen> createState() => _Connect4ScreenState();
}

class _Connect4ScreenState extends State<Connect4Screen> {
  static const int _cols = 7, _rows = 6;
  static const _redColor = Color(0xFFE53935);
  static const _yellowColor = Color(0xFFFFD835);
  static const _boardColor = Color(0xFF1565C0);

  C4Mode _mode = C4Mode.menu;

  // WiFi multiplayer
  WifiGameService? _wifiService;
  bool _isWifiGame = false;
  bool _showWifiLobby = false;

  late List<List<C4Disc>> _board;
  C4Disc _turn = C4Disc.red;
  C4Disc _winner = C4Disc.none;
  List<(int, int)>? _winCells;
  bool _gameOver = false;
  bool _vsAI = false;
  bool _aiThinking = false;
  C4Disc _humanDisc = C4Disc.red;
  final _rng = Random();

  @override
  void initState() { super.initState(); _initBoard(); }

  @override
  void dispose() {
    _wifiService?.dispose();
    super.dispose();
  }

  void _initBoard() {
    _board = List.generate(_rows, (_) => List.filled(_cols, C4Disc.none));
    _turn = C4Disc.red; _winner = C4Disc.none; _winCells = null;
    _gameOver = false; _aiThinking = false;
  }

  void _startGame(bool vsAI, C4Disc humanDisc) {
    _initBoard(); _vsAI = vsAI; _humanDisc = humanDisc;
    _mode = C4Mode.playing; setState(() {});
    if (_vsAI && _turn != _humanDisc) _scheduleAI();
  }

  int? _dropDisc(int col) {
    for (int r = _rows - 1; r >= 0; r--) {
      if (_board[r][col] == C4Disc.none) { _board[r][col] = _turn; return r; }
    }
    return null;
  }

  void _onColTap(int col) {
    if (_gameOver || _aiThinking) return;
    if (_vsAI && _turn != _humanDisc) return;
    // In WiFi mode, only allow moves on local player's turn
    if (_isWifiGame && _turn != _humanDisc) return;

    // Send move to opponent over WiFi
    if (_isWifiGame && _wifiService != null) {
      _wifiService!.send({'type': 'move', 'col': col});
    }

    _playCol(col);
  }

  void _playCol(int col) {
    final row = _dropDisc(col);
    if (row == null) return;
    HapticFeedback.mediumImpact();
    _checkWin(row, col);
    if (!_gameOver) {
      _turn = _turn == C4Disc.red ? C4Disc.yellow : C4Disc.red;
      if (_isBoardFull()) { _gameOver = true; }
    }
    setState(() {});
    if (!_gameOver && _vsAI && _turn != _humanDisc) _scheduleAI();
  }

  bool _isBoardFull() => _board[0].every((d) => d != C4Disc.none);

  void _checkWin(int r, int c) {
    final disc = _board[r][c];
    final dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (final (dr, dc) in dirs) {
      final cells = <(int, int)>[(r, c)];
      for (int d = 1; d < 4; d++) {
        final nr = r + dr * d, nc = c + dc * d;
        if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols || _board[nr][nc] != disc) break;
        cells.add((nr, nc));
      }
      for (int d = 1; d < 4; d++) {
        final nr = r - dr * d, nc = c - dc * d;
        if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols || _board[nr][nc] != disc) break;
        cells.add((nr, nc));
      }
      if (cells.length >= 4) {
        _winner = disc; _winCells = cells; _gameOver = true;
        HapticFeedback.heavyImpact(); return;
      }
    }
  }

  void _scheduleAI() {
    _aiThinking = true; setState(() {});
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _gameOver) return;
      final col = _findAIMove();
      _playCol(col);
      _aiThinking = false;
      if (mounted) setState(() {});
    });
  }

  int _findAIMove() {
    final ai = _turn;
    final validCols = <int>[];
    for (int c = 0; c < _cols; c++) {
      if (_board[0][c] == C4Disc.none) validCols.add(c);
    }
    if (validCols.isEmpty) return 0;

    // Use minimax with alpha-beta pruning, depth 5
    int bestCol = validCols[_rng.nextInt(validCols.length)];
    int bestScore = -100000000;
    // Evaluate center columns first for better pruning
    validCols.sort((a, b) => (a - 3).abs().compareTo((b - 3).abs()));

    for (final col in validCols) {
      final row = _simDrop(col, ai);
      if (row == null) continue;
      int score;
      if (_simCheckWin(row, col, ai)) {
        score = 10000000;
      } else {
        score = _minimax(4, false, ai, -100000000, 100000000);
      }
      _board[row][col] = C4Disc.none;
      // Add small randomness to equally-scored moves so AI isn't robotic
      score += _rng.nextInt(3);
      if (score > bestScore) {
        bestScore = score;
        bestCol = col;
      }
    }
    return bestCol;
  }

  int? _simDrop(int col, C4Disc disc) {
    for (int r = _rows - 1; r >= 0; r--) {
      if (_board[r][col] == C4Disc.none) { _board[r][col] = disc; return r; }
    }
    return null;
  }

  bool _simCheckWin(int r, int c, C4Disc disc) {
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (final (dr, dc) in dirs) {
      int count = 1;
      for (int d = 1; d < 4; d++) {
        final nr = r + dr * d, nc = c + dc * d;
        if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols || _board[nr][nc] != disc) break;
        count++;
      }
      for (int d = 1; d < 4; d++) {
        final nr = r - dr * d, nc = c - dc * d;
        if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols || _board[nr][nc] != disc) break;
        count++;
      }
      if (count >= 4) return true;
    }
    return false;
  }

  int _minimax(int depth, bool isMax, C4Disc aiDisc, int alpha, int beta) {
    final oppDisc = aiDisc == C4Disc.red ? C4Disc.yellow : C4Disc.red;

    if (depth == 0) return _evaluateBoard(aiDisc);

    // Check for full board
    bool isFull = true;
    for (int c = 0; c < _cols; c++) {
      if (_board[0][c] == C4Disc.none) { isFull = false; break; }
    }
    if (isFull) return 0;

    final colOrder = [3, 2, 4, 1, 5, 0, 6]; // center-first for better pruning

    if (isMax) {
      int maxScore = -100000000;
      for (final col in colOrder) {
        final row = _simDrop(col, aiDisc);
        if (row == null) continue;
        int score;
        if (_simCheckWin(row, col, aiDisc)) {
          score = 1000000 + depth; // prefer faster wins
        } else {
          score = _minimax(depth - 1, false, aiDisc, alpha, beta);
        }
        _board[row][col] = C4Disc.none;
        if (score > maxScore) maxScore = score;
        if (maxScore > alpha) alpha = maxScore;
        if (alpha >= beta) break;
      }
      return maxScore;
    } else {
      int minScore = 100000000;
      for (final col in colOrder) {
        final row = _simDrop(col, oppDisc);
        if (row == null) continue;
        int score;
        if (_simCheckWin(row, col, oppDisc)) {
          score = -(1000000 + depth); // prefer blocking faster losses
        } else {
          score = _minimax(depth - 1, true, aiDisc, alpha, beta);
        }
        _board[row][col] = C4Disc.none;
        if (score < minScore) minScore = score;
        if (minScore < beta) beta = minScore;
        if (alpha >= beta) break;
      }
      return minScore;
    }
  }

  int _evaluateBoard(C4Disc aiDisc) {
    final oppDisc = aiDisc == C4Disc.red ? C4Disc.yellow : C4Disc.red;
    int score = 0;

    // Center column preference
    for (int r = 0; r < _rows; r++) {
      if (_board[r][3] == aiDisc) score += 3;
      if (_board[r][2] == aiDisc || _board[r][4] == aiDisc) score += 1;
    }

    // Evaluate all windows of 4
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        for (final (dr, dc) in dirs) {
          // Check if window fits
          final er = r + dr * 3, ec = c + dc * 3;
          if (er < 0 || er >= _rows || ec < 0 || ec >= _cols) continue;

          int aiCount = 0, oppCount = 0, empty = 0;
          for (int i = 0; i < 4; i++) {
            final cell = _board[r + dr * i][c + dc * i];
            if (cell == aiDisc) aiCount++;
            else if (cell == oppDisc) oppCount++;
            else empty++;
          }

          // Score the window
          if (aiCount == 3 && empty == 1) score += 50;
          else if (aiCount == 2 && empty == 2) score += 5;
          if (oppCount == 3 && empty == 1) score -= 80; // heavily penalize threats
          else if (oppCount == 2 && empty == 2) score -= 3;
        }
      }
    }

    return score;
  }

  // ── WiFi ─────────────────────────────────────────────────────────────────

  void _startWifiGame(WifiGameService service) {
    _wifiService = service;
    _isWifiGame = true;
    _showWifiLobby = false;
    _initBoard();
    // Host plays red (first), client plays yellow (second)
    _humanDisc = service.isHost ? C4Disc.red : C4Disc.yellow;
    _vsAI = false;
    _mode = C4Mode.playing;

    _wifiService!.onMessage = (msg) {
      if (!mounted) return;
      final type = msg['type'] as String? ?? '';
      if (type == 'move') {
        final col = msg['col'] as int;
        if (!_gameOver) {
          _playCol(col);
        }
      }
    };
    _wifiService!.onDisconnected = () {
      if (!mounted) return;
      _wifiService = null;
      _isWifiGame = false;
      setState(() => _mode = C4Mode.menu);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opponent disconnected'), backgroundColor: GameTheme.accentAlt));
    };

    setState(() {});
  }

  void _disposeWifi() {
    _wifiService?.dispose();
    _wifiService = null;
    _isWifiGame = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_showWifiLobby) {
      return WifiLobby(
        gameName: 'Connect 4',
        maxPlayers: 2,
        onGameStart: _startWifiGame,
        onBack: () => setState(() => _showWifiLobby = false),
      );
    }
    if (_mode == C4Mode.menu) return _buildMenu();
    return _buildGame();
  }

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(title: const Text('Connect 4'), leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
        onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Connect 4'),
          ),
        ]),
      body: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dot(_redColor, 36), const SizedBox(width: 12), _dot(_yellowColor, 36)]),
          const SizedBox(height: 8),
          const Text('Connect 4', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
          const SizedBox(height: 32),
          _menuBtn(Icons.smart_toy_rounded, '1 Player', 'Play against AI', () => _showPicker(true)),
          const SizedBox(height: 12),
          _menuBtn(Icons.people_rounded, '2 Players', 'Local multiplayer', () => _startGame(false, C4Disc.red)),
          const SizedBox(height: 12),
          _menuBtn(Icons.wifi_rounded, 'WiFi Multiplayer', 'Play over WiFi', () => setState(() => _showWifiLobby = true)),
        ]))),
    );
  }

  Widget _dot(Color c, double s) => Container(width: s, height: s,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 8)]));

  Widget _menuBtn(IconData icon, String label, String sub, VoidCallback onTap) {
    return GestureDetector(onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(color: GameTheme.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border)),
        child: Row(children: [
          Icon(icon, color: GameTheme.accent, size: 26), const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
            Text(sub, style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary))]),
          const Spacer(),
          const Icon(Icons.arrow_forward_ios_rounded, color: GameTheme.textSecondary, size: 16)])));
  }

  void _showPicker(bool vsAI) {
    showModalBottomSheet(context: context, backgroundColor: GameTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: GameTheme.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Choose your color', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _colorOpt(C4Disc.red, vsAI)),
            const SizedBox(width: 16),
            Expanded(child: _colorOpt(C4Disc.yellow, vsAI))])])));
  }

  Widget _colorOpt(C4Disc disc, bool vsAI) {
    final c = disc == C4Disc.red ? _redColor : _yellowColor;
    final name = disc == C4Disc.red ? 'Red' : 'Yellow';
    return GestureDetector(onTap: () { Navigator.pop(context); _startGame(vsAI, disc); },
      child: Container(padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(color: GameTheme.background, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c, width: 2)),
        child: Column(children: [
          _dot(c, 48), const SizedBox(height: 12),
          Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c)),
          Text(disc == C4Disc.red ? 'Goes first' : 'Goes second',
            style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary))])));
  }

  Widget _buildGame() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: Text(_isWifiGame ? 'Connect 4 — WiFi' : _vsAI ? 'Connect 4 — vs AI' : 'Connect 4 — 2 Players'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () { _disposeWifi(); setState(() => _mode = C4Mode.menu); }),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
          onPressed: () { _initBoard(); setState(() {}); if (_vsAI && _turn != _humanDisc) _scheduleAI(); })]),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final boardW = min(constraints.maxWidth - 32, 820.0);
        final cellSize = boardW / _cols;
        final boardH = cellSize * _rows;

        return Column(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_aiThinking) ...[
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: GameTheme.accent)),
                const SizedBox(width: 8)],
              Text(_gameOver
                ? _winner == C4Disc.none ? "It's a draw!" : '${_winner == C4Disc.red ? "Red" : "Yellow"} wins!'
                : _aiThinking ? 'AI thinking...' : "${_turn == C4Disc.red ? "Red" : "Yellow"}'s turn",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  color: _gameOver && _winner != C4Disc.none
                    ? (_winner == C4Disc.red ? _redColor : _yellowColor)
                    : GameTheme.accent))])),

          const Spacer(),

          // Board
          Center(child: Container(
            width: boardW, height: boardH,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: _boardColor, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: _boardColor.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))]),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _rows * _cols,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _cols),
              itemBuilder: (_, i) {
                final r = i ~/ _cols, c = i % _cols;
                final disc = _board[r][c];
                final isWin = _winCells?.contains((r, c)) ?? false;
                return GestureDetector(
                  onTap: () => _onColTap(c),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: disc == C4Disc.none ? const Color(0xFF0D47A1)
                        : disc == C4Disc.red ? _redColor : _yellowColor,
                      border: isWin ? Border.all(color: Colors.white, width: 3) : null,
                      boxShadow: disc != C4Disc.none ? [
                        BoxShadow(color: (disc == C4Disc.red ? _redColor : _yellowColor).withValues(alpha: isWin ? 0.7 : 0.3),
                          blurRadius: isWin ? 12 : 4)] : null)));
              }))),

          const Spacer(),

          if (_gameOver) Padding(padding: const EdgeInsets.only(bottom: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ElevatedButton(onPressed: () { _initBoard(); setState(() {}); if (_vsAI && _turn != _humanDisc) _scheduleAI(); },
                style: ElevatedButton.styleFrom(backgroundColor: GameTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Rematch', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () => setState(() => _mode = C4Mode.menu),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: GameTheme.accent),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Menu', style: TextStyle(fontWeight: FontWeight.w700, color: GameTheme.accent)))])),

          Padding(padding: const EdgeInsets.only(bottom: 20),
            child: Text('Tap a column to drop', style: TextStyle(color: GameTheme.textSecondary.withValues(alpha: 0.5), fontSize: 12))),
        ]);
      })),
    );
  }
}
