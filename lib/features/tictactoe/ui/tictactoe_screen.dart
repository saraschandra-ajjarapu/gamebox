import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/services/wifi_game_service.dart';
import '../../../core/widgets/wifi_lobby.dart';

enum TTTMode { menu, playing }
enum TTTPlayer { x, o, none }

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen>
    with TickerProviderStateMixin {
  late List<TTTPlayer> _board;
  TTTPlayer _turn = TTTPlayer.x;
  TTTPlayer _winner = TTTPlayer.none;
  List<int>? _winLine;
  bool _gameOver = false;
  bool _vsAI = false;
  bool _aiThinking = false;
  TTTPlayer _humanMark = TTTPlayer.x;
  int _xWins = 0;
  int _oWins = 0;
  int _draws = 0;

  TTTMode _mode = TTTMode.menu;

  // WiFi multiplayer
  WifiGameService? _wifiService;
  bool _isWifiGame = false;
  bool _showWifiLobby = false;

  // Animation for placed marks
  final Map<int, AnimationController> _markAnims = {};

  // Win line animation
  AnimationController? _winAnimCtrl;

  @override
  void initState() {
    super.initState();
    _initBoard();
  }

  @override
  void dispose() {
    _wifiService?.dispose();
    for (final ctrl in _markAnims.values) {
      ctrl.dispose();
    }
    _winAnimCtrl?.dispose();
    super.dispose();
  }

  void _initBoard() {
    _board = List.filled(9, TTTPlayer.none);
    _turn = TTTPlayer.x;
    _winner = TTTPlayer.none;
    _winLine = null;
    _gameOver = false;
    _aiThinking = false;
    for (final ctrl in _markAnims.values) {
      ctrl.dispose();
    }
    _markAnims.clear();
    _winAnimCtrl?.dispose();
    _winAnimCtrl = null;
  }

  void _startGame({required bool vsAI, TTTPlayer humanMark = TTTPlayer.x}) {
    _initBoard();
    _vsAI = vsAI;
    _humanMark = humanMark;
    _mode = TTTMode.playing;
    setState(() {});

    // If AI goes first
    if (_vsAI && _humanMark == TTTPlayer.o) {
      _scheduleAI();
    }
  }

  void _onTap(int index) {
    if (_gameOver || _board[index] != TTTPlayer.none || _aiThinking) return;
    if (_vsAI && _turn != _humanMark) return;
    // In WiFi mode, only allow moves on local player's turn
    if (_isWifiGame && _turn != _humanMark) return;

    // Send move to opponent over WiFi
    if (_isWifiGame && _wifiService != null) {
      _wifiService!.send({'type': 'move', 'row': index ~/ 3, 'col': index % 3});
    }

    _placeMark(index);
  }

  void _placeMark(int index) {
    _board[index] = _turn;

    // Animate the mark
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _markAnims[index] = ctrl;
    ctrl.forward();

    HapticFeedback.lightImpact();

    // Check win
    _checkWin();
    if (_gameOver) {
      setState(() {});
      return;
    }

    // Switch turn
    _turn = _turn == TTTPlayer.x ? TTTPlayer.o : TTTPlayer.x;
    setState(() {});

    // AI move
    if (_vsAI && _turn != _humanMark && !_gameOver) {
      _scheduleAI();
    }
  }

  void _checkWin() {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], // cols
      [0, 4, 8], [2, 4, 6],             // diags
    ];

    for (final line in lines) {
      if (_board[line[0]] != TTTPlayer.none &&
          _board[line[0]] == _board[line[1]] &&
          _board[line[1]] == _board[line[2]]) {
        _winner = _board[line[0]];
        _winLine = line;
        _gameOver = true;
        if (_winner == TTTPlayer.x) _xWins++;
        if (_winner == TTTPlayer.o) _oWins++;
        HapticFeedback.heavyImpact();

        // Animate win line
        _winAnimCtrl = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 600),
        );
        _winAnimCtrl!.forward();
        return;
      }
    }

    // Draw check
    if (!_board.contains(TTTPlayer.none)) {
      _gameOver = true;
      _draws++;
    }
  }

  // ── AI ──────────────────────────────────────────────────────────────────

  void _scheduleAI() {
    _aiThinking = true;
    setState(() {});
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _gameOver) return;
      final move = _findAIMove();
      if (move != null) _placeMark(move);
      _aiThinking = false;
      if (mounted) setState(() {});
    });
  }

  int? _findAIMove() {
    final aiMark = _humanMark == TTTPlayer.x ? TTTPlayer.o : TTTPlayer.x;
    final humanMark = _humanMark;

    // 1. Win if possible
    for (int i = 0; i < 9; i++) {
      if (_board[i] == TTTPlayer.none) {
        _board[i] = aiMark;
        if (_wouldWin(aiMark)) { _board[i] = TTTPlayer.none; return i; }
        _board[i] = TTTPlayer.none;
      }
    }
    // 2. Block opponent win
    for (int i = 0; i < 9; i++) {
      if (_board[i] == TTTPlayer.none) {
        _board[i] = humanMark;
        if (_wouldWin(humanMark)) { _board[i] = TTTPlayer.none; return i; }
        _board[i] = TTTPlayer.none;
      }
    }
    // 3. Take center
    if (_board[4] == TTTPlayer.none) return 4;
    // 4. Take corner
    for (final c in [0, 2, 6, 8]) {
      if (_board[c] == TTTPlayer.none) return c;
    }
    // 5. Take any edge
    for (final e in [1, 3, 5, 7]) {
      if (_board[e] == TTTPlayer.none) return e;
    }
    return null;
  }

  bool _wouldWin(TTTPlayer p) {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    for (final l in lines) {
      if (_board[l[0]] == p && _board[l[1]] == p && _board[l[2]] == p) return true;
    }
    return false;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  // ── WiFi ─────────────────────────────────────────────────────────────────

  void _startWifiGame(WifiGameService service) {
    _wifiService = service;
    _isWifiGame = true;
    _showWifiLobby = false;
    _initBoard();
    // Host plays X, client plays O
    _humanMark = service.isHost ? TTTPlayer.x : TTTPlayer.o;
    _vsAI = false;
    _mode = TTTMode.playing;

    _wifiService!.onMessage = (msg) {
      if (!mounted) return;
      final type = msg['type'] as String? ?? '';
      if (type == 'move') {
        final index = (msg['row'] as int) * 3 + (msg['col'] as int);
        if (_board[index] == TTTPlayer.none && !_gameOver) {
          _placeMark(index);
        }
      }
    };
    _wifiService!.onDisconnected = () {
      if (!mounted) return;
      _wifiService = null;
      _isWifiGame = false;
      setState(() => _mode = TTTMode.menu);
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
        gameName: 'Tic Tac Toe',
        maxPlayers: 2,
        onGameStart: _startWifiGame,
        onBack: () => setState(() => _showWifiLobby = false),
      );
    }
    if (_mode == TTTMode.menu) return _buildMenu();
    return _buildGame();
  }

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Tic Tac Toe'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Tic Tac Toe'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // X and O display
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('X', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900,
                      color: const Color(0xFF4ECDC4))),
                  const SizedBox(width: 16),
                  Text('O', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900,
                      color: const Color(0xFFFF6B6B))),
                ],
              ),
              const SizedBox(height: 32),

              _menuButton(
                icon: Icons.smart_toy_rounded,
                label: '1 Player',
                subtitle: 'Play against AI',
                onTap: () => _showMarkPicker(vsAI: true),
              ),
              const SizedBox(height: 16),
              _menuButton(
                icon: Icons.people_rounded,
                label: '2 Players',
                subtitle: 'Local multiplayer',
                onTap: () => _startGame(vsAI: false),
              ),
              const SizedBox(height: 16),
              _menuButton(
                icon: Icons.wifi_rounded,
                label: 'WiFi Multiplayer',
                subtitle: 'Play over WiFi',
                onTap: () => setState(() => _showWifiLobby = true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: GameTheme.accent, size: 28),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: GameTheme.textPrimary)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: GameTheme.textSecondary)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, color: GameTheme.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }

  void _showMarkPicker({required bool vsAI}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: GameTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: GameTheme.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Choose your mark',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _markOption(TTTPlayer.x, vsAI)),
                const SizedBox(width: 16),
                Expanded(child: _markOption(TTTPlayer.o, vsAI)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _markOption(TTTPlayer mark, bool vsAI) {
    final isX = mark == TTTPlayer.x;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
        _startGame(vsAI: vsAI, humanMark: mark);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: GameTheme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isX ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B), width: 2),
        ),
        child: Column(
          children: [
            Text(isX ? 'X' : 'O',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900,
                    color: isX ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B))),
            const SizedBox(height: 8),
            Text(isX ? 'Goes first' : 'Goes second',
                style: const TextStyle(fontSize: 13, color: GameTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildGame() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: Text(_isWifiGame ? 'Tic Tac Toe — WiFi' : _vsAI ? 'Tic Tac Toe — vs AI' : 'Tic Tac Toe — 2 Players'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () {
            _disposeWifi();
            setState(() { _mode = TTTMode.menu; });
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
            onPressed: () {
              _initBoard();
              setState(() {});
              if (_vsAI && _humanMark == TTTPlayer.o) _scheduleAI();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gridSize = min(constraints.maxWidth - 48, constraints.maxHeight * 0.55);

            return Column(
              children: [
                const SizedBox(height: 12),

                // Score bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _scoreChip('X', _xWins, const Color(0xFF4ECDC4)),
                      _scoreChip('Draw', _draws, GameTheme.textSecondary),
                      _scoreChip('O', _oWins, const Color(0xFFFF6B6B)),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Status
                SizedBox(
                  height: 40,
                  child: Center(
                    child: _aiThinking
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: GameTheme.accent)),
                              const SizedBox(width: 8),
                              const Text('AI thinking...', style: TextStyle(color: GameTheme.accent, fontSize: 16)),
                            ],
                          )
                        : Text(
                            _gameOver
                                ? (_winner == TTTPlayer.none
                                    ? "It's a draw!"
                                    : '${_winner == TTTPlayer.x ? "X" : "O"} wins!')
                                : "${_turn == TTTPlayer.x ? "X" : "O"}'s turn",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _gameOver
                                  ? (_winner == TTTPlayer.x
                                      ? const Color(0xFF4ECDC4)
                                      : _winner == TTTPlayer.o
                                          ? const Color(0xFFFF6B6B)
                                          : GameTheme.textSecondary)
                                  : GameTheme.accent,
                            ),
                          ),
                  ),
                ),

                const Spacer(),

                // Grid
                Center(
                  child: SizedBox(
                    width: gridSize,
                    height: gridSize,
                    child: CustomPaint(
                      painter: _GridLinesPainter(),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 9,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                        ),
                        itemBuilder: (_, i) => _buildCell(i, gridSize / 3),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Game over buttons
                if (_gameOver)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            _initBoard();
                            setState(() {});
                            if (_vsAI && _humanMark == TTTPlayer.o) _scheduleAI();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GameTheme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Play Again',
                              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => setState(() { _mode = TTTMode.menu; }),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: GameTheme.accent),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Menu',
                              style: TextStyle(fontWeight: FontWeight.w700, color: GameTheme.accent)),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _scoreChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: GameTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameTheme.border),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildCell(int index, double cellSize) {
    final mark = _board[index];
    final isWinCell = _winLine?.contains(index) ?? false;

    return GestureDetector(
      onTap: () => _onTap(index),
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: mark == TTTPlayer.none
              ? null
              : _markAnims.containsKey(index)
                  ? AnimatedBuilder(
                      animation: _markAnims[index]!,
                      builder: (_, __) {
                        final t = _markAnims[index]!.value;
                        return Transform.scale(
                          scale: Curves.elasticOut.transform(t.clamp(0.0, 1.0)),
                          child: _buildMark(mark, cellSize, isWinCell),
                        );
                      },
                    )
                  : _buildMark(mark, cellSize, isWinCell),
        ),
      ),
    );
  }

  Widget _buildMark(TTTPlayer mark, double cellSize, bool isWinCell) {
    final size = cellSize * 0.55;
    if (mark == TTTPlayer.x) {
      return CustomPaint(
        size: Size(size, size),
        painter: _XPainter(
          color: const Color(0xFF4ECDC4),
          glow: isWinCell,
        ),
      );
    } else {
      return CustomPaint(
        size: Size(size, size),
        painter: _OPainter(
          color: const Color(0xFFFF6B6B),
          glow: isWinCell,
        ),
      );
    }
  }
}

// ── Grid lines painter ────────────────────────────────────────────────────

class _GridLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2A3A4A)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final cellW = size.width / 3;
    final cellH = size.height / 3;
    final margin = 12.0;

    // Vertical lines
    canvas.drawLine(Offset(cellW, margin), Offset(cellW, size.height - margin), paint);
    canvas.drawLine(Offset(cellW * 2, margin), Offset(cellW * 2, size.height - margin), paint);
    // Horizontal lines
    canvas.drawLine(Offset(margin, cellH), Offset(size.width - margin, cellH), paint);
    canvas.drawLine(Offset(margin, cellH * 2), Offset(size.width - margin, cellH * 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── X painter ─────────────────────────────────────────────────────────────

class _XPainter extends CustomPainter {
  final Color color;
  final bool glow;
  _XPainter({required this.color, this.glow = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (glow) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = size.width * 0.22
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), glowPaint);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), glowPaint);
    }

    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_XPainter old) => old.glow != glow;
}

// ── O painter ─────────────────────────────────────────────────────────────

class _OPainter extends CustomPainter {
  final Color color;
  final bool glow;
  _OPainter({required this.color, this.glow = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.14
      ..style = PaintingStyle.stroke;

    if (glow) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = size.width * 0.22
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, radius, glowPaint);
    }

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_OPainter old) => old.glow != glow;
}
