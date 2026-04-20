import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';

// ── Constants ─────────────────────────────────────────────────────────────

enum LudoColor { red, green, yellow, blue }
enum LudoMode { menu, playing }
enum PlayerType { human, ai }

const _ludoColors = {
  LudoColor.red: Color(0xFFE53935),
  LudoColor.green: Color(0xFF43A047),
  LudoColor.yellow: Color(0xFFFDD835),
  LudoColor.blue: Color(0xFF1E88E5),
};

const _ludoDarkColors = {
  LudoColor.red: Color(0xFFB71C1C),
  LudoColor.green: Color(0xFF1B5E20),
  LudoColor.yellow: Color(0xFFF9A825),
  LudoColor.blue: Color(0xFF0D47A1),
};

// Each color's path around the board (52 shared squares + 5 home stretch)
// Positions 0-51 are the shared track, 52-56 are home column
// Starting positions on the shared track for each color
const _startPositions = {
  LudoColor.red: 0,
  LudoColor.green: 13,
  LudoColor.yellow: 26,
  LudoColor.blue: 39,
};

// Safe spots on the shared track (starting positions + star positions)
const _safeSpots = {0, 8, 13, 21, 26, 34, 39, 47};

class LudoPiece {
  final LudoColor color;
  final int index; // 0-3 for each player
  int position; // -1 = home base, 0-51 = track, 52-56 = home column
  bool isFinished;

  LudoPiece(this.color, this.index) : position = -1, isFinished = false;

  void reset() {
    position = -1;
    isFinished = false;
  }
}

class LudoPlayer {
  final LudoColor color;
  final PlayerType type;
  final List<LudoPiece> pieces;

  LudoPlayer(this.color, this.type)
      : pieces = List.generate(4, (i) => LudoPiece(color, i));

  bool get allFinished => pieces.every((p) => p.isFinished);
  int get finishedCount => pieces.where((p) => p.isFinished).length;

  void reset() {
    for (final p in pieces) {
      p.reset();
    }
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────

class LudoGameScreen extends StatefulWidget {
  const LudoGameScreen({super.key});

  @override
  State<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends State<LudoGameScreen>
    with TickerProviderStateMixin {
  LudoMode _mode = LudoMode.menu;
  int _numPlayers = 2; // human players

  late List<LudoPlayer> _players;
  int _currentPlayerIndex = 0;
  int _diceValue = 0;
  bool _diceRolled = false;
  bool _gameOver = false;
  String _status = '';
  List<int> _finishOrder = [];
  LudoColor _humanColor = LudoColor.red;

  // Dice animation
  AnimationController? _diceAnimCtrl;
  bool _rolling = false;

  // Board effects
  Offset? _burstGridPos;
  bool _celebrateHome = false;
  LudoColor? _celebrateHomeColor;

  final _random = Random();

  LudoPlayer get _currentPlayer => _players[_currentPlayerIndex];

  @override
  void dispose() {
    _diceAnimCtrl?.dispose();
    super.dispose();
  }

  void _initGame() {
    _players = [];

    if (_numPlayers == 1) {
      // 1 human + 1 AI opponent (just 2 players for faster gameplay)
      final aiColor = switch (_humanColor) {
        LudoColor.red => LudoColor.green,
        LudoColor.green => LudoColor.red,
        LudoColor.yellow => LudoColor.blue,
        LudoColor.blue => LudoColor.yellow,
      };
      final colors = [_humanColor, aiColor];
      for (int i = 0; i < 2; i++) {
        _players.add(LudoPlayer(colors[i], i == 0 ? PlayerType.human : PlayerType.ai));
      }
    } else if (_numPlayers == 2) {
      // 2 humans, opposite corners
      final otherColor = switch (_humanColor) {
        LudoColor.red => LudoColor.yellow,
        LudoColor.green => LudoColor.blue,
        LudoColor.yellow => LudoColor.red,
        LudoColor.blue => LudoColor.green,
      };
      _players.add(LudoPlayer(_humanColor, PlayerType.human));
      _players.add(LudoPlayer(otherColor, PlayerType.human));
    } else {
      // 3 or 4 players
      final colors = [LudoColor.red, LudoColor.green, LudoColor.yellow, LudoColor.blue];
      for (int i = 0; i < _numPlayers; i++) {
        _players.add(LudoPlayer(colors[i], PlayerType.human));
      }
    }

    _currentPlayerIndex = 0;
    _diceValue = 0;
    _diceRolled = false;
    _gameOver = false;
    _finishOrder = [];
    _status = '${_colorName(_currentPlayer.color)}\'s turn — Roll the dice';
    for (final p in _players) {
      p.reset();
    }
  }

  void _startGame(int numHumans, {LudoColor color = LudoColor.red}) {
    _numPlayers = numHumans;
    _humanColor = color;
    _initGame();
    _mode = LudoMode.playing;
    setState(() {});

    if (_currentPlayer.type == PlayerType.ai) {
      _scheduleAI();
    }
  }

  String _colorName(LudoColor c) => switch (c) {
    LudoColor.red => 'Red',
    LudoColor.green => 'Green',
    LudoColor.yellow => 'Yellow',
    LudoColor.blue => 'Blue',
  };

  // ── Dice ────────────────────────────────────────────────────────────────

  void _rollDice() {
    if (_diceRolled || _rolling || _gameOver) return;

    _rolling = true;
    _diceAnimCtrl?.dispose();
    _diceAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    HapticFeedback.mediumImpact();

    // Animate dice faces during roll
    int animCount = 0;
    _diceAnimCtrl!.addListener(() {
      final newCount = (_diceAnimCtrl!.value * 8).floor();
      if (newCount != animCount) {
        animCount = newCount;
        setState(() => _diceValue = _random.nextInt(6) + 1);
      }
    });

    _diceAnimCtrl!.forward().then((_) {
      _diceValue = _random.nextInt(6) + 1;
      _rolling = false;
      _diceRolled = true;

      // Check if any move is possible
      final movable = _getMovablePieces();
      if (movable.isEmpty) {
        _status = '${_colorName(_currentPlayer.color)} rolled $_diceValue — no moves';
        setState(() {});
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          _nextTurn();
        });
      } else if (movable.length == 1 && _currentPlayer.type == PlayerType.ai) {
        _status = '${_colorName(_currentPlayer.color)} rolled $_diceValue';
        setState(() {});
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          _movePiece(movable.first);
        });
      } else {
        _status = '${_colorName(_currentPlayer.color)} rolled $_diceValue — pick a piece';
        setState(() {});

        if (_currentPlayer.type == PlayerType.ai) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            _aiPickPiece(movable);
          });
        }
      }
    });

    setState(() {});
  }

  List<LudoPiece> _getMovablePieces() {
    final movable = <LudoPiece>[];
    for (final piece in _currentPlayer.pieces) {
      if (piece.isFinished) continue;
      if (piece.position == -1) {
        // Can only leave base on a 6
        if (_diceValue == 6) movable.add(piece);
      } else {
        // Check if move is valid (not overshooting home)
        final newPos = piece.position + _diceValue;
        if (newPos <= 56) movable.add(piece);
      }
    }
    return movable;
  }

  // ── Move ────────────────────────────────────────────────────────────────

  void _onPieceTap(LudoPiece piece) {
    if (!_diceRolled || _rolling || _gameOver) return;
    if (piece.color != _currentPlayer.color) return;
    if (_currentPlayer.type == PlayerType.ai) return;
    if (piece.isFinished) return;

    final movable = _getMovablePieces();
    if (!movable.contains(piece)) return;

    _movePiece(piece);
  }

  void _movePiece(LudoPiece piece) {
    bool captured = false;
    bool reachedHome = false;

    if (piece.position == -1) {
      // Move out of base to start of own path (relative position 0)
      piece.position = 0;
      // Check for capture at start
      captured = _checkCapture(piece);
    } else {
      piece.position += _diceValue;
      if (piece.position == 56) {
        // Reached home!
        piece.isFinished = true;
        reachedHome = true;
        HapticFeedback.heavyImpact();
        _celebrateHome = true;
        _celebrateHomeColor = piece.color;
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _celebrateHome = false);
        });

        if (_currentPlayer.allFinished) {
          _finishOrder.add(_currentPlayerIndex);
          if (_finishOrder.length >= _players.length - 1) {
            // Find last player
            for (int i = 0; i < _players.length; i++) {
              if (!_finishOrder.contains(i)) _finishOrder.add(i);
            }
            _gameOver = true;
            _status = '${_colorName(_players[_finishOrder[0]].color)} wins!';
            setState(() {});
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _showWinDialog();
            });
            return;
          }
        }
      } else if (piece.position <= 51) {
        captured = _checkCapture(piece);
      }
    }

    HapticFeedback.lightImpact();

    // Extra turn on: rolling 6, capturing a piece, or reaching home
    if (_diceValue == 6 || captured || reachedHome) {
      _diceRolled = false;
      _status = '${_colorName(_currentPlayer.color)} gets another turn!';
      setState(() {});

      if (_currentPlayer.type == PlayerType.ai) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          _rollDice();
        });
      }
    } else {
      _nextTurn();
    }
  }

  bool _checkCapture(LudoPiece piece) {
    if (piece.position < 0 || piece.position > 51) return false;

    // Convert relative position to absolute track position for safe spot check
    final absPos = _absolutePosition(piece);
    if (_safeSpots.contains(absPos)) return false;

    bool captured = false;
    for (final player in _players) {
      if (player.color == piece.color) continue;
      for (final other in player.pieces) {
        if (other.isFinished || other.position < 0 || other.position > 51) continue;
        if (_absolutePosition(other) == absPos) {
          // Capture! Send back to base
          _burstGridPos = _trackCoordinates[absPos];
          other.position = -1;
          captured = true;
          HapticFeedback.heavyImpact();
          _status = '${_colorName(piece.color)} captures ${_colorName(other.color)}!';
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted) setState(() => _burstGridPos = null);
          });
        }
      }
    }
    return captured;
  }

  int _absolutePosition(LudoPiece piece) {
    if (piece.position < 0 || piece.position > 51) return -1;
    return (_startPositions[piece.color]! + piece.position) % 52;
  }

  void _nextTurn() {
    final playerCount = _players.length;
    int next = (_currentPlayerIndex + 1) % playerCount;
    int attempts = 0;
    while (_players[next].allFinished && attempts < playerCount) {
      next = (next + 1) % playerCount;
      attempts++;
    }
    _currentPlayerIndex = next;
    _diceRolled = false;
    _diceValue = 0;
    _status = '${_colorName(_currentPlayer.color)}\'s turn — Roll the dice';
    setState(() {});

    if (_currentPlayer.type == PlayerType.ai) {
      _scheduleAI();
    }
  }

  // ── AI ──────────────────────────────────────────────────────────────────

  void _scheduleAI() {
    // AI plays at human-like pace — no rush
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || _gameOver) return;
      _rollDice();
    });
  }

  void _aiPickPiece(List<LudoPiece> movable) {
    LudoPiece? best;
    int bestScore = -99999;

    for (final piece in movable) {
      int score = 0;

      if (piece.position == -1) {
        // Leaving base on a 6
        // Count how many pieces are still in base
        final inBase = _currentPlayer.pieces.where((p) => p.position == -1 && !p.isFinished).length;
        final onBoard = _currentPlayer.pieces.where((p) => p.position >= 0 && !p.isFinished).length;

        if (onBoard == 0) {
          score = 200; // Must get a piece out if none on board
        } else if (inBase >= 3) {
          score = 120; // Get pieces out when most are stuck in base
        } else if (inBase >= 2) {
          score = 60;  // Moderate priority to bring out more pieces
        } else {
          score = 25;  // Low priority if already have pieces out
        }

        // Check if start position is occupied by own piece (avoid stacking)
        final startAbs = _startPositions[piece.color]!;
        for (final p in _currentPlayer.pieces) {
          if (p != piece && !p.isFinished && p.position >= 0 && p.position <= 51) {
            if (_absolutePosition(p) == startAbs) {
              score -= 40; // Don't stack on own start
            }
          }
        }
      } else {
        final newPos = piece.position + _diceValue;

        if (newPos == 56) {
          score = 500; // Reaching home -- highest priority
        } else if (newPos > 51) {
          // Home stretch -- strongly prefer advancing pieces close to home
          score = 300 + newPos;
        } else {
          final absNew = (_startPositions[piece.color]! + newPos) % 52;
          final absCur = _absolutePosition(piece);

          // Check if this move would capture an opponent
          bool canCapture = false;
          bool captureAdvancedPiece = false;
          if (!_safeSpots.contains(absNew)) {
            for (final opp in _players) {
              if (opp.color == piece.color) continue;
              for (final op in opp.pieces) {
                if (!op.isFinished && op.position >= 0 && op.position <= 51) {
                  if (_absolutePosition(op) == absNew) {
                    canCapture = true;
                    // Extra reward for capturing pieces that are far advanced
                    if (op.position > 30) captureAdvancedPiece = true;
                  }
                }
              }
            }
          }

          if (canCapture) {
            score = captureAdvancedPiece ? 400 : 250; // Capture, especially advanced opponents
          }

          // Landing on a safe spot is valuable
          if (_safeSpots.contains(absNew)) {
            score += 40;
          }

          // Check vulnerability at destination -- is the new position unsafe?
          if (!_safeSpots.contains(absNew) && !canCapture) {
            bool vulnerable = false;
            for (final opp in _players) {
              if (opp.color == piece.color) continue;
              for (final op in opp.pieces) {
                if (op.isFinished || op.position < 0 || op.position > 51) continue;
                final oppAbs = _absolutePosition(op);
                // Check if any opponent is within 1-6 steps behind our destination
                for (int d = 1; d <= 6; d++) {
                  if ((oppAbs + d) % 52 == absNew) {
                    vulnerable = true;
                    break;
                  }
                }
                if (vulnerable) break;
              }
              if (vulnerable) break;
            }
            if (vulnerable) score -= 30;
          }

          // Check if we're currently vulnerable and would move to safety
          if (!_safeSpots.contains(absCur)) {
            bool currentlyVulnerable = false;
            for (final opp in _players) {
              if (opp.color == piece.color) continue;
              for (final op in opp.pieces) {
                if (op.isFinished || op.position < 0 || op.position > 51) continue;
                final oppAbs = _absolutePosition(op);
                for (int d = 1; d <= 6; d++) {
                  if ((oppAbs + d) % 52 == absCur) {
                    currentlyVulnerable = true;
                    break;
                  }
                }
                if (currentlyVulnerable) break;
              }
              if (currentlyVulnerable) break;
            }
            if (currentlyVulnerable) score += 35; // Bonus for escaping danger
          }

          // Prefer advancing pieces that are closer to home (higher position)
          score += (newPos * 2);

          // Bonus for entering home stretch (position > 51)
          if (newPos > 46) score += 20; // Almost at home stretch entry
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = piece;
      }
    }

    if (best != null) _movePiece(best);
  }

  // ── Win Dialog ──────────────────────────────────────────────────────────

  void _showWinDialog() {
    final winner = _players[_finishOrder[0]];
    final color = _ludoColors[winner.color]!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: GameTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Icon(Icons.emoji_events_rounded, size: 72, color: color),
            const SizedBox(height: 16),
            Text('${_colorName(winner.color)} Wins!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 8),
            Text(winner.type == PlayerType.ai ? 'Better luck next time!' : 'Congratulations!',
              style: const TextStyle(fontSize: 16, color: GameTheme.textSecondary)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () { Navigator.pop(context); _initGame(); setState(() {}); },
                  style: ElevatedButton.styleFrom(backgroundColor: color,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Play Again', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () { Navigator.pop(context); setState(() => _mode = LudoMode.menu); },
                  style: OutlinedButton.styleFrom(side: BorderSide(color: color),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Menu', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Board Effects ──────────────────────────────────────────────────────

  Widget _buildBurstEffect(double boardSize) {
    final cell = boardSize / 15;
    final cx = _burstGridPos!.dx * cell + cell / 2;
    final cy = _burstGridPos!.dy * cell + cell / 2;
    return Positioned(
      left: cx - cell * 1.5,
      top: cy - cell * 1.5,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        builder: (_, v, __) => SizedBox(
          width: cell * 3,
          height: cell * 3,
          child: CustomPaint(painter: _BurstPainter(progress: v)),
        ),
      ),
    );
  }

  Widget _buildHomeCelebration(double boardSize) {
    final cell = boardSize / 15;
    final color = _ludoColors[_celebrateHomeColor!]!;
    return Positioned(
      left: 7.5 * cell - cell * 2,
      top: 7.5 * cell - cell * 2,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        builder: (_, v, __) => Opacity(
          opacity: (1.0 - v).clamp(0.0, 1.0),
          child: SizedBox(
            width: cell * 4,
            height: cell * 4,
            child: CustomPaint(painter: _CelebrationPainter(progress: v, color: color)),
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_mode == LudoMode.menu) return _buildMenu();
    return _buildGame();
  }

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Ludo'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Ludo'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ludo colored dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: LudoColor.values.map((c) => Container(
                  width: 32, height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: _ludoColors[c],
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _ludoColors[c]!.withValues(alpha: 0.4), blurRadius: 8)],
                  ),
                )).toList(),
              ),
              const SizedBox(height: 12),
              const Text('Ludo', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800,
                  color: GameTheme.textPrimary)),
              const SizedBox(height: 36),

              _menuButton(icon: Icons.person, label: '1 Player', subtitle: 'You vs AI', onTap: () => _showColorPicker(1)),
              const SizedBox(height: 12),
              _menuButton(icon: Icons.people, label: '2 Players', subtitle: 'Local multiplayer', onTap: () => _showColorPicker(2)),
              const SizedBox(height: 12),
              _menuButton(icon: Icons.groups, label: '3 Players', subtitle: '3 players', onTap: () => _startGame(3)),
              const SizedBox(height: 12),
              _menuButton(icon: Icons.groups_rounded, label: '4 Players', subtitle: 'All players', onTap: () => _startGame(4)),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPicker(int numHumans) {
    showModalBottomSheet(
      context: context, backgroundColor: GameTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: GameTheme.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Choose your color', style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: LudoColor.values.map((c) => GestureDetector(
              onTap: () {
                Navigator.pop(context);
                HapticFeedback.mediumImpact();
                _startGame(numHumans, color: c);
              },
              child: Column(children: [
                Container(width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: _ludoColors[c], shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                    boxShadow: [BoxShadow(color: _ludoColors[c]!.withValues(alpha: 0.4), blurRadius: 10)])),
                const SizedBox(height: 8),
                Text(_colorName(c), style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: _ludoColors[c])),
              ]),
            )).toList()),
        ])));
  }

  Widget _menuButton({required IconData icon, required String label,
      required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: GameTheme.accent, size: 24),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, color: GameTheme.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildGame() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Ludo'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => setState(() => _mode = LudoMode.menu),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
            onPressed: () { _initGame(); setState(() {}); },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = min(min(constraints.maxWidth - 24, constraints.maxHeight - 200), 700.0);

            return Column(
              children: [
                // Status
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Text(_status,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      color: _ludoColors[_currentPlayer.color]),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Player indicators
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _players.map((p) => Flexible(child: _playerChip(p))).toList(),
                  ),
                ),

                const SizedBox(height: 8),

                // Board
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: boardSize,
                      height: boardSize,
                      child: CustomPaint(
                        painter: _LudoBoardPainter(),
                        child: Stack(
                          children: [
                            // Pieces on board
                            for (final player in _players)
                              for (final piece in player.pieces)
                                if (!piece.isFinished)
                                  _buildPieceOnBoard(piece, boardSize),
                            // Capture burst effect
                            if (_burstGridPos != null)
                              _buildBurstEffect(boardSize),
                            // Home celebration
                            if (_celebrateHome && _celebrateHomeColor != null)
                              _buildHomeCelebration(boardSize),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Dice + roll button
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Dice
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: _rolling ? GameTheme.accent : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (_rolling ? GameTheme.accent : Colors.white).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _diceValue > 0
                            ? _buildDiceFace(_diceValue)
                            : Icon(Icons.casino_rounded,
                                color: GameTheme.background, size: 32),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Roll button
                    if (!_diceRolled && !_gameOver && _currentPlayer.type == PlayerType.human)
                      ElevatedButton(
                        onPressed: _rolling ? null : _rollDice,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ludoColors[_currentPlayer.color],
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Roll', style: TextStyle(fontSize: 18,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                  ],
                ),

                if (_gameOver)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () { _initGame(); setState(() {}); },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GameTheme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Play Again', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => setState(() => _mode = LudoMode.menu),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: GameTheme.accent),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Menu', style: TextStyle(fontWeight: FontWeight.w700, color: GameTheme.accent)),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _playerChip(LudoPlayer player) {
    final active = player == _currentPlayer && !_gameOver;
    final color = _ludoColors[player.color]!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.2) : GameTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? color : GameTheme.border, width: active ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('${player.finishedCount}/4',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: active ? color : GameTheme.textSecondary)),
          if (player.type == PlayerType.ai)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(Icons.smart_toy_rounded, size: 10,
                color: active ? color : GameTheme.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildDiceFace(int value) {
    // Simple dot pattern for dice
    return SizedBox(
      width: 44, height: 44,
      child: CustomPaint(
        painter: _DiceFacePainter(value: value),
      ),
    );
  }

  int _countPiecesAtSamePosition(LudoPiece piece) {
    int count = 0;
    final absPos = piece.position >= 0 && piece.position <= 51
        ? _absolutePosition(piece) : -999;
    for (final player in _players) {
      for (final other in player.pieces) {
        if (other.isFinished || other.position < 0) continue;
        if (other.color == piece.color && other.position == piece.position) {
          count++;
        } else if (other.color != piece.color && other.position >= 0 && other.position <= 51 &&
            _absolutePosition(other) == absPos) {
          count++;
        }
      }
    }
    return count;
  }

  Widget _buildPieceOnBoard(LudoPiece piece, double boardSize) {
    final cellSize = boardSize / 15;
    final pos = _getPieceScreenPosition(piece, boardSize);
    if (pos == null) return const SizedBox.shrink();

    final color = _ludoColors[piece.color]!;
    final darkColor = _ludoDarkColors[piece.color]!;
    final isMovable = _diceRolled && piece.color == _currentPlayer.color &&
        _getMovablePieces().contains(piece);
    final stackCount = _countPiecesAtSamePosition(piece);

    // Slightly offset stacked pieces so they're visible
    final stackOffset = stackCount > 1 ? (piece.index % 2 == 0 ? -3.0 : 3.0) : 0.0;

    return Positioned(
      left: pos.dx - cellSize * 0.35 + stackOffset,
      top: pos.dy - cellSize * 0.35 + stackOffset,
      child: GestureDetector(
        onTap: () => _onPieceTap(piece),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: cellSize * 0.7,
          height: cellSize * 0.7,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [color, darkColor],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: isMovable ? 2.5 : 1.5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: isMovable ? 0.6 : 0.3),
                blurRadius: isMovable ? 10 : 4, spreadRadius: isMovable ? 2 : 0),
            ],
          ),
            ),
            if (stackCount > 1)
              Positioned(
                right: -4, top: -4,
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                  ),
                  child: Center(
                    child: Text('$stackCount',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800,
                        color: darkColor)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Offset? _getPieceScreenPosition(LudoPiece piece, double boardSize) {
    final cell = boardSize / 15;

    if (piece.position == -1) {
      // Home base positions — match _drawHomeBase spot centers exactly
      // Spots drawn at (col+dx+0.5)*cell where dx in {1.5, 3.5}
      // Piece center = o.dx * cell + cell/2, so o.dx = spotCenter/cell - 0.5
      final baseOffsets = {
        LudoColor.red: [Offset(1.5, 1.5), Offset(3.5, 1.5), Offset(1.5, 3.5), Offset(3.5, 3.5)],
        LudoColor.green: [Offset(10.5, 1.5), Offset(12.5, 1.5), Offset(10.5, 3.5), Offset(12.5, 3.5)],
        LudoColor.yellow: [Offset(10.5, 10.5), Offset(12.5, 10.5), Offset(10.5, 12.5), Offset(12.5, 12.5)],
        LudoColor.blue: [Offset(1.5, 10.5), Offset(3.5, 10.5), Offset(1.5, 12.5), Offset(3.5, 12.5)],
      };
      final offsets = baseOffsets[piece.color]!;
      final o = offsets[piece.index];
      return Offset(o.dx * cell + cell / 2, o.dy * cell + cell / 2);
    }

    if (piece.position >= 52) {
      // Home column
      final homeStep = piece.position - 51;
      final homePositions = {
        LudoColor.red: List.generate(5, (i) => Offset(1 + i.toDouble(), 7)),
        LudoColor.green: List.generate(5, (i) => Offset(7, 1 + i.toDouble())),
        LudoColor.yellow: List.generate(5, (i) => Offset(13 - i.toDouble(), 7)),
        LudoColor.blue: List.generate(5, (i) => Offset(7, 13 - i.toDouble())),
      };
      if (homeStep <= 0 || homeStep > 5) return null;
      final pos = homePositions[piece.color]![homeStep - 1];
      return Offset(pos.dx * cell + cell / 2, pos.dy * cell + cell / 2);
    }

    // Shared track — convert relative position to absolute
    final absPos = (_startPositions[piece.color]! + piece.position) % 52;
    final trackPos = _trackCoordinates[absPos];
    return Offset(trackPos.dx * cell + cell / 2, trackPos.dy * cell + cell / 2);
  }
}

// Track coordinates for 52 positions around the board (col, row)
const _trackCoordinates = [
  // Red start (left side, going up)
  Offset(1, 6), Offset(2, 6), Offset(3, 6), Offset(4, 6), Offset(5, 6),
  // Turn up
  Offset(6, 5), Offset(6, 4), Offset(6, 3), Offset(6, 2), Offset(6, 1), Offset(6, 0),
  // Turn right (top)
  Offset(7, 0), Offset(8, 0),
  // Green start (top side, going right)
  Offset(8, 1), Offset(8, 2), Offset(8, 3), Offset(8, 4), Offset(8, 5),
  // Turn right
  Offset(9, 6), Offset(10, 6), Offset(11, 6), Offset(12, 6), Offset(13, 6), Offset(14, 6),
  // Turn down (right)
  Offset(14, 7), Offset(14, 8),
  // Yellow start (right side, going down)
  Offset(13, 8), Offset(12, 8), Offset(11, 8), Offset(10, 8), Offset(9, 8),
  // Turn down
  Offset(8, 9), Offset(8, 10), Offset(8, 11), Offset(8, 12), Offset(8, 13), Offset(8, 14),
  // Turn left (bottom)
  Offset(7, 14), Offset(6, 14),
  // Blue start (bottom side, going left)
  Offset(6, 13), Offset(6, 12), Offset(6, 11), Offset(6, 10), Offset(6, 9),
  // Turn left
  Offset(5, 8), Offset(4, 8), Offset(3, 8), Offset(2, 8), Offset(1, 8), Offset(0, 8),
  // Turn up (left)
  Offset(0, 7), Offset(0, 6),
];

// ── Board Painter ─────────────────────────────────────────────────────────

class _LudoBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final bgPaint = Paint()..color = const Color(0xFFFAF3E0);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(12)),
      bgPaint,
    );

    // Home bases (colored quadrants)
    _drawHomeBase(canvas, cell, 0, 0, _ludoColors[LudoColor.red]!);
    _drawHomeBase(canvas, cell, 9, 0, _ludoColors[LudoColor.green]!);
    _drawHomeBase(canvas, cell, 9, 9, _ludoColors[LudoColor.yellow]!);
    _drawHomeBase(canvas, cell, 0, 9, _ludoColors[LudoColor.blue]!);

    // Center home triangle
    _drawCenterHome(canvas, cell);

    // Track cells
    final trackPaint = Paint()..color = Colors.white;
    final trackBorder = Paint()..color = const Color(0xFFDDDDDD)..style = PaintingStyle.stroke..strokeWidth = 0.5;

    for (final pos in _trackCoordinates) {
      final rect = Rect.fromLTWH(pos.dx * cell, pos.dy * cell, cell, cell);
      canvas.drawRect(rect, trackPaint);
      canvas.drawRect(rect, trackBorder);
    }

    // Safe spots (star markers)
    final starPaint = Paint()..color = const Color(0xFFE0E0E0);
    for (final i in _safeSpots) {
      final pos = _trackCoordinates[i];
      canvas.drawCircle(
        Offset(pos.dx * cell + cell / 2, pos.dy * cell + cell / 2),
        cell * 0.2, starPaint,
      );
    }

    // Home columns (colored paths to center)
    _drawHomeColumn(canvas, cell, _ludoColors[LudoColor.red]!,
        List.generate(5, (i) => Offset(1 + i.toDouble(), 7)));
    _drawHomeColumn(canvas, cell, _ludoColors[LudoColor.green]!,
        List.generate(5, (i) => Offset(7, 1 + i.toDouble())));
    _drawHomeColumn(canvas, cell, _ludoColors[LudoColor.yellow]!,
        List.generate(5, (i) => Offset(13 - i.toDouble(), 7)));
    _drawHomeColumn(canvas, cell, _ludoColors[LudoColor.blue]!,
        List.generate(5, (i) => Offset(7, 13 - i.toDouble())));

    // Colored start cells
    _drawColoredCell(canvas, cell, _trackCoordinates[0], _ludoColors[LudoColor.red]!);
    _drawColoredCell(canvas, cell, _trackCoordinates[13], _ludoColors[LudoColor.green]!);
    _drawColoredCell(canvas, cell, _trackCoordinates[26], _ludoColors[LudoColor.yellow]!);
    _drawColoredCell(canvas, cell, _trackCoordinates[39], _ludoColors[LudoColor.blue]!);
  }

  void _drawHomeBase(Canvas canvas, double cell, double col, double row, Color color) {
    final rect = Rect.fromLTWH(col * cell, row * cell, 6 * cell, 6 * cell);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = color);

    // Inner white circle area for pieces
    final inner = Rect.fromLTWH((col + 0.8) * cell, (row + 0.8) * cell, 4.4 * cell, 4.4 * cell);
    canvas.drawRRect(RRect.fromRectAndRadius(inner, const Radius.circular(6)),
        Paint()..color = Colors.white.withValues(alpha: 0.9));

    // Piece spots
    for (final dx in [1.5, 3.5]) {
      for (final dy in [1.5, 3.5]) {
        canvas.drawCircle(
          Offset((col + dx + 0.5) * cell, (row + dy + 0.5) * cell),
          cell * 0.35,
          Paint()..color = color.withValues(alpha: 0.3),
        );
      }
    }
  }

  void _drawCenterHome(Canvas canvas, double cell) {
    final center = Offset(7.5 * cell, 7.5 * cell);

    // Draw 4 triangles
    for (int i = 0; i < 4; i++) {
      final colors = [_ludoColors[LudoColor.red]!, _ludoColors[LudoColor.green]!,
          _ludoColors[LudoColor.yellow]!, _ludoColors[LudoColor.blue]!];
      final path = Path();
      switch (i) {
        case 0: // Left (Red)
          path.moveTo(6 * cell, 6 * cell); path.lineTo(center.dx, center.dy);
          path.lineTo(6 * cell, 9 * cell); path.close();
        case 1: // Top (Green)
          path.moveTo(6 * cell, 6 * cell); path.lineTo(center.dx, center.dy);
          path.lineTo(9 * cell, 6 * cell); path.close();
        case 2: // Right (Yellow)
          path.moveTo(9 * cell, 6 * cell); path.lineTo(center.dx, center.dy);
          path.lineTo(9 * cell, 9 * cell); path.close();
        case 3: // Bottom (Blue)
          path.moveTo(6 * cell, 9 * cell); path.lineTo(center.dx, center.dy);
          path.lineTo(9 * cell, 9 * cell); path.close();
      }
      canvas.drawPath(path, Paint()..color = colors[i]);
    }
  }

  void _drawHomeColumn(Canvas canvas, double cell, Color color, List<Offset> positions) {
    for (final pos in positions) {
      final rect = Rect.fromLTWH(pos.dx * cell, pos.dy * cell, cell, cell);
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.4));
      canvas.drawRect(rect, Paint()..color = const Color(0xFFDDDDDD)..style = PaintingStyle.stroke..strokeWidth = 0.5);
    }
  }

  void _drawColoredCell(Canvas canvas, double cell, Offset pos, Color color) {
    final rect = Rect.fromLTWH(pos.dx * cell, pos.dy * cell, cell, cell);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Dice Face Painter ─────────────────────────────────────────────────────

class _DiceFacePainter extends CustomPainter {
  final int value;
  _DiceFacePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = const Color(0xFF1A1A2E);
    final r = size.width * 0.09;
    final cx = size.width / 2, cy = size.height / 2;
    final d = size.width * 0.28;

    final positions = <Offset>[];
    switch (value) {
      case 1: positions.addAll([Offset(cx, cy)]);
      case 2: positions.addAll([Offset(cx - d, cy - d), Offset(cx + d, cy + d)]);
      case 3: positions.addAll([Offset(cx - d, cy + d), Offset(cx, cy), Offset(cx + d, cy - d)]);
      case 4: positions.addAll([Offset(cx - d, cy - d), Offset(cx + d, cy - d), Offset(cx - d, cy + d), Offset(cx + d, cy + d)]);
      case 5: positions.addAll([Offset(cx - d, cy - d), Offset(cx + d, cy - d), Offset(cx, cy), Offset(cx - d, cy + d), Offset(cx + d, cy + d)]);
      case 6: positions.addAll([Offset(cx - d, cy - d), Offset(cx + d, cy - d), Offset(cx - d, cy), Offset(cx + d, cy), Offset(cx - d, cy + d), Offset(cx + d, cy + d)]);
    }
    for (final p in positions) {
      canvas.drawCircle(p, r, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_DiceFacePainter old) => old.value != value;
}

// ── Capture Burst Painter ────────────────────────────────────────────────

class _BurstPainter extends CustomPainter {
  final double progress;
  _BurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Expanding rings
    for (int i = 0; i < 3; i++) {
      final delay = i * 0.15;
      final p = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final paint = Paint()
        ..color = Color.fromRGBO(255, 60, 60, (1.0 - p) * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1.0 - p);
      canvas.drawCircle(center, maxRadius * p, paint);
    }

    // Burst particles
    final particlePaint = Paint()..color = Color.fromRGBO(255, 165, 0, (1.0 - progress) * 0.8);
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * pi;
      final dist = maxRadius * progress * 0.8;
      final pos = Offset(center.dx + cos(angle) * dist, center.dy + sin(angle) * dist);
      canvas.drawCircle(pos, 3 * (1.0 - progress), particlePaint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}

// ── Home Celebration Painter ─────────────────────────────────────────────

class _CelebrationPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CelebrationPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Star burst particles
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * pi;
      final dist = maxRadius * progress;
      final pos = Offset(center.dx + cos(angle) * dist, center.dy + sin(angle) * dist);
      canvas.drawCircle(pos, 4 * (1.0 - progress),
        Paint()..color = color.withValues(alpha: (1.0 - progress) * 0.7));
    }

    // Inner sparkle ring
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * pi + progress * pi;
      final dist = maxRadius * progress * 0.6;
      final pos = Offset(center.dx + cos(angle) * dist, center.dy + sin(angle) * dist);
      canvas.drawCircle(pos, 3 * (1.0 - progress),
        Paint()..color = Colors.white.withValues(alpha: (1.0 - progress) * 0.5));
    }

    // Center glow
    canvas.drawCircle(center, maxRadius * 0.3 * (1.0 + progress * 0.5),
      Paint()..color = color.withValues(alpha: (1.0 - progress) * 0.3));
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) => old.progress != progress;
}
