import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/services/wifi_game_service.dart';
import '../../../core/widgets/wifi_lobby.dart';

enum DBMode { menu, playing }

class DotsBoxesScreen extends StatefulWidget {
  const DotsBoxesScreen({super.key});
  @override
  State<DotsBoxesScreen> createState() => _DotsBoxesScreenState();
}

class _DotsBoxesScreenState extends State<DotsBoxesScreen> {
  static const int _gridSize = 7; // 7x7 dots = 6x6 boxes
  static const _p1Color = GameTheme.accent;
  static const _p2Color = GameTheme.accentAlt;

  DBMode _mode = DBMode.menu;
  bool _vsAI = false;

  // WiFi multiplayer
  WifiGameService? _wifiService;
  bool _isWifiGame = false;
  bool _showWifiLobby = false;
  bool _aiThinking = false;

  // Lines: horizontal[row][col] and vertical[row][col]
  late List<List<bool>> _hLines; // _gridSize rows x (_gridSize-1) cols
  late List<List<bool>> _vLines; // (_gridSize-1) rows x _gridSize cols
  late List<List<int>> _boxes;   // (_gridSize-1) x (_gridSize-1), 0=none, 1=p1, 2=p2
  int _turn = 1; // 1 or 2
  int _p1Score = 0, _p2Score = 0;
  bool _gameOver = false;
  final _rng = Random();

  @override
  void dispose() {
    _wifiService?.dispose();
    super.dispose();
  }

  void _initGame() {
    _hLines = List.generate(_gridSize, (_) => List.filled(_gridSize - 1, false));
    _vLines = List.generate(_gridSize - 1, (_) => List.filled(_gridSize, false));
    _boxes = List.generate(_gridSize - 1, (_) => List.filled(_gridSize - 1, 0));
    _turn = 1; _p1Score = 0; _p2Score = 0; _gameOver = false; _aiThinking = false;
  }

  void _startGame(bool vsAI) {
    _initGame(); _vsAI = vsAI; _mode = DBMode.playing; setState(() {});
  }

  void _drawHLine(int row, int col) {
    if (_hLines[row][col] || _gameOver || _aiThinking) return;
    if (_vsAI && _turn == 2) return;
    // In WiFi mode, only allow moves on local player's turn
    if (_isWifiGame && _turn != _localPlayer) return;

    // Send move to opponent over WiFi
    if (_isWifiGame && _wifiService != null) {
      _wifiService!.send({'type': 'hline', 'row': row, 'col': col});
    }

    _placeHLine(row, col);
  }

  void _drawVLine(int row, int col) {
    if (_vLines[row][col] || _gameOver || _aiThinking) return;
    if (_vsAI && _turn == 2) return;
    // In WiFi mode, only allow moves on local player's turn
    if (_isWifiGame && _turn != _localPlayer) return;

    // Send move to opponent over WiFi
    if (_isWifiGame && _wifiService != null) {
      _wifiService!.send({'type': 'vline', 'row': row, 'col': col});
    }

    _placeVLine(row, col);
  }

  void _placeHLine(int row, int col) {
    _hLines[row][col] = true;
    HapticFeedback.lightImpact();
    bool scored = _checkBoxes();
    if (!scored) _turn = _turn == 1 ? 2 : 1;
    _checkGameOver();
    setState(() {});
    if (!_gameOver && _vsAI && _turn == 2) _scheduleAI();
  }

  void _placeVLine(int row, int col) {
    _vLines[row][col] = true;
    HapticFeedback.lightImpact();
    bool scored = _checkBoxes();
    if (!scored) _turn = _turn == 1 ? 2 : 1;
    _checkGameOver();
    setState(() {});
    if (!_gameOver && _vsAI && _turn == 2) _scheduleAI();
  }

  bool _checkBoxes() {
    bool scored = false;
    for (int r = 0; r < _gridSize - 1; r++) {
      for (int c = 0; c < _gridSize - 1; c++) {
        if (_boxes[r][c] == 0 &&
            _hLines[r][c] && _hLines[r + 1][c] &&
            _vLines[r][c] && _vLines[r][c + 1]) {
          _boxes[r][c] = _turn;
          if (_turn == 1) _p1Score++; else _p2Score++;
          scored = true;
          HapticFeedback.heavyImpact();
        }
      }
    }
    return scored;
  }

  void _checkGameOver() {
    if (_p1Score + _p2Score >= (_gridSize - 1) * (_gridSize - 1)) _gameOver = true;
  }

  void _scheduleAI() {
    _aiThinking = true; setState(() {});
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _gameOver) return;
      _aiMove();
      _aiThinking = false;
      if (mounted) setState(() {});
    });
  }

  void _aiMove() {
    // Try to complete a box first
    for (int r = 0; r < _gridSize - 1; r++) {
      for (int c = 0; c < _gridSize - 1; c++) {
        if (_boxes[r][c] != 0) continue;
        int sides = 0;
        if (_hLines[r][c]) sides++;
        if (_hLines[r + 1][c]) sides++;
        if (_vLines[r][c]) sides++;
        if (_vLines[r][c + 1]) sides++;
        if (sides == 3) {
          if (!_hLines[r][c]) { _placeHLine(r, c); return; }
          if (!_hLines[r + 1][c]) { _placeHLine(r + 1, c); return; }
          if (!_vLines[r][c]) { _placeVLine(r, c); return; }
          if (!_vLines[r][c + 1]) { _placeVLine(r, c + 1); return; }
        }
      }
    }
    // Avoid giving opponent a box (avoid 3rd side)
    final safe = <(bool, int, int)>[]; // (isHorizontal, row, col)
    for (int r = 0; r < _gridSize; r++) {
      for (int c = 0; c < _gridSize - 1; c++) {
        if (!_hLines[r][c]) {
          if (!_wouldGiveBox(true, r, c)) safe.add((true, r, c));
        }
      }
    }
    for (int r = 0; r < _gridSize - 1; r++) {
      for (int c = 0; c < _gridSize; c++) {
        if (!_vLines[r][c]) {
          if (!_wouldGiveBox(false, r, c)) safe.add((false, r, c));
        }
      }
    }
    if (safe.isNotEmpty) {
      final pick = safe[_rng.nextInt(safe.length)];
      if (pick.$1) _placeHLine(pick.$2, pick.$3); else _placeVLine(pick.$2, pick.$3);
      return;
    }
    // Forced to give a box — pick any
    for (int r = 0; r < _gridSize; r++) {
      for (int c = 0; c < _gridSize - 1; c++) {
        if (!_hLines[r][c]) { _placeHLine(r, c); return; }
      }
    }
    for (int r = 0; r < _gridSize - 1; r++) {
      for (int c = 0; c < _gridSize; c++) {
        if (!_vLines[r][c]) { _placeVLine(r, c); return; }
      }
    }
  }

  bool _wouldGiveBox(bool isH, int row, int col) {
    if (isH) {
      // Check box above (row-1, col) and below (row, col)
      if (row > 0) {
        int s = 0;
        if (_hLines[row - 1][col]) s++;
        if (_vLines[row - 1][col]) s++;
        if (_vLines[row - 1][col + 1]) s++;
        if (s >= 2) return true;
      }
      if (row < _gridSize - 1) {
        int s = 0;
        if (_hLines[row + 1][col]) s++;
        if (_vLines[row][col]) s++;
        if (_vLines[row][col + 1]) s++;
        if (s >= 2) return true;
      }
    } else {
      // Check box left (row, col-1) and right (row, col)
      if (col > 0) {
        int s = 0;
        if (_hLines[row][col - 1]) s++;
        if (_hLines[row + 1][col - 1]) s++;
        if (_vLines[row][col - 1]) s++;
        if (s >= 2) return true;
      }
      if (col < _gridSize - 1) {
        int s = 0;
        if (_hLines[row][col]) s++;
        if (_hLines[row + 1][col]) s++;
        if (_vLines[row][col + 1]) s++;
        if (s >= 2) return true;
      }
    }
    return false;
  }

  // ── WiFi ─────────────────────────────────────────────────────────────────

  void _startWifiGame(WifiGameService service) {
    _wifiService = service;
    _isWifiGame = true;
    _showWifiLobby = false;
    _initGame();
    _vsAI = false;
    _mode = DBMode.playing;

    _wifiService!.onMessage = (msg) {
      if (!mounted) return;
      final type = msg['type'] as String? ?? '';
      final row = msg['row'] as int? ?? 0;
      final col = msg['col'] as int? ?? 0;
      if (type == 'hline') {
        if (!_hLines[row][col] && !_gameOver) {
          _placeHLine(row, col);
        }
      } else if (type == 'vline') {
        if (!_vLines[row][col] && !_gameOver) {
          _placeVLine(row, col);
        }
      }
    };
    _wifiService!.onDisconnected = () {
      if (!mounted) return;
      _wifiService = null;
      _isWifiGame = false;
      setState(() => _mode = DBMode.menu);
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

  // WiFi: host is player 1, client is player 2
  int get _localPlayer => (_isWifiGame && _wifiService != null)
      ? (_wifiService!.isHost ? 1 : 2) : 0;

  @override
  Widget build(BuildContext context) {
    if (_showWifiLobby) {
      return WifiLobby(
        gameName: 'Dots & Boxes',
        maxPlayers: 2,
        onGameStart: _startWifiGame,
        onBack: () => setState(() => _showWifiLobby = false),
      );
    }
    if (_mode == DBMode.menu) return _buildMenu();
    return _buildGame();
  }

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(title: const Text('Dots & Boxes'), leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
        onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Dots & Boxes'),
          ),
        ]),
      body: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.grid_4x4_rounded, size: 56, color: GameTheme.accent),
          const SizedBox(height: 8),
          const Text('Dots & Boxes', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
          const SizedBox(height: 32),
          _menuBtn(Icons.smart_toy_rounded, '1 Player', 'vs AI', () => _startGame(true)),
          const SizedBox(height: 12),
          _menuBtn(Icons.people_rounded, '2 Players', 'Local', () => _startGame(false)),
          const SizedBox(height: 12),
          _menuBtn(Icons.wifi_rounded, 'WiFi Multiplayer', 'Play over WiFi', () => setState(() => _showWifiLobby = true)),
        ]))));
  }

  Widget _menuBtn(IconData icon, String label, String sub, VoidCallback onTap) {
    return GestureDetector(onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(color: GameTheme.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border)),
        child: Row(children: [Icon(icon, color: GameTheme.accent, size: 26), const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
            Text(sub, style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary))]),
          const Spacer(), const Icon(Icons.arrow_forward_ios_rounded, color: GameTheme.textSecondary, size: 16)])));
  }

  Widget _buildGame() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(title: Text(_isWifiGame ? 'Dots & Boxes — WiFi' : 'Dots & Boxes'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () { _disposeWifi(); setState(() => _mode = DBMode.menu); }),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
          onPressed: () { _initGame(); setState(() {}); })]),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final boardSize = min(constraints.maxWidth - 32, constraints.maxHeight - 180);
        final gap = boardSize / _gridSize;
        final gridWidth = (_gridSize - 1) * gap;
        final offsetX = (boardSize - gridWidth) / 2;
        final offsetY = (boardSize - gridWidth) / 2;

        return Column(children: [
          // Scores
          Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _scoreChip('Player 1', _p1Score, _p1Color, _turn == 1),
              _scoreChip(_vsAI ? 'AI' : 'Player 2', _p2Score, _p2Color, _turn == 2)])),

          if (_gameOver) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_p1Score > _p2Score ? 'Player 1 wins!' : _p2Score > _p1Score ? '${_vsAI ? "AI" : "Player 2"} wins!' : 'Draw!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GameTheme.gold))),

          const Spacer(),

          // Board — centered
          Center(child: SizedBox(width: boardSize, height: boardSize,
            child: CustomPaint(
              painter: _DBBoardPainter(
                gridSize: _gridSize, hLines: _hLines, vLines: _vLines,
                boxes: _boxes, p1Color: _p1Color, p2Color: _p2Color),
              child: Stack(children: [
                // Horizontal line tap targets
                for (int r = 0; r < _gridSize; r++)
                  for (int c = 0; c < _gridSize - 1; c++)
                    Positioned(
                      left: offsetX + (c + 0.5) * gap - gap * 0.3, top: offsetY + r * gap - 10, width: gap * 0.6, height: 20,
                      child: GestureDetector(onTap: () => _drawHLine(r, c),
                        child: Container(color: Colors.transparent))),
                // Vertical line tap targets
                for (int r = 0; r < _gridSize - 1; r++)
                  for (int c = 0; c < _gridSize; c++)
                    Positioned(
                      left: offsetX + c * gap - 10, top: offsetY + (r + 0.5) * gap - gap * 0.3, width: 20, height: gap * 0.6,
                      child: GestureDetector(onTap: () => _drawVLine(r, c),
                        child: Container(color: Colors.transparent))),
              ])))),

          const Spacer(),

          if (_gameOver) Padding(padding: const EdgeInsets.only(bottom: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ElevatedButton(onPressed: () { _initGame(); setState(() {}); },
                style: ElevatedButton.styleFrom(backgroundColor: GameTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Rematch', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () => setState(() => _mode = DBMode.menu),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: GameTheme.accent),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Menu', style: TextStyle(fontWeight: FontWeight.w700, color: GameTheme.accent)))])),

          const SizedBox(height: 16),
        ]);
      })),
    );
  }

  Widget _scoreChip(String label, int score, Color color, bool active) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : GameTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? color : GameTheme.border, width: active ? 2 : 1)),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? color : GameTheme.textSecondary)),
        Text('$score', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: active ? color : GameTheme.textPrimary))]));
  }
}

class _DBBoardPainter extends CustomPainter {
  final int gridSize;
  final List<List<bool>> hLines, vLines;
  final List<List<int>> boxes;
  final Color p1Color, p2Color;

  _DBBoardPainter({required this.gridSize, required this.hLines, required this.vLines,
    required this.boxes, required this.p1Color, required this.p2Color});

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate gap so grid fits within the smaller dimension
    final boardSpan = min(size.width, size.height);
    final gap = boardSpan / (gridSize);
    final dotR = 5.0;

    // Center the grid
    final gridWidth = (gridSize - 1) * gap;
    final gridHeight = (gridSize - 1) * gap;
    final offsetX = (size.width - gridWidth) / 2;
    final offsetY = (size.height - gridHeight) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);

    // Boxes
    for (int r = 0; r < gridSize - 1; r++) {
      for (int c = 0; c < gridSize - 1; c++) {
        if (boxes[r][c] != 0) {
          final color = boxes[r][c] == 1 ? p1Color : p2Color;
          canvas.drawRect(
            Rect.fromLTWH(c * gap + dotR, r * gap + dotR, gap - dotR * 2, gap - dotR * 2),
            Paint()..color = color.withValues(alpha: 0.2));
        }
      }
    }

    // Horizontal lines
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize - 1; c++) {
        final paint = Paint()
          ..color = hLines[r][c] ? Colors.white : const Color(0xFF2A3A4A)
          ..strokeWidth = hLines[r][c] ? 4 : 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(c * gap, r * gap), Offset((c + 1) * gap, r * gap), paint);
      }
    }

    // Vertical lines
    for (int r = 0; r < gridSize - 1; r++) {
      for (int c = 0; c < gridSize; c++) {
        final paint = Paint()
          ..color = vLines[r][c] ? Colors.white : const Color(0xFF2A3A4A)
          ..strokeWidth = vLines[r][c] ? 4 : 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(c * gap, r * gap), Offset(c * gap, (r + 1) * gap), paint);
      }
    }

    // Dots
    final dotPaint = Paint()..color = Colors.white;
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        canvas.drawCircle(Offset(c * gap, r * gap), dotR, dotPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
