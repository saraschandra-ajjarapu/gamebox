import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/services/wifi_game_service.dart';
import '../../../core/widgets/wifi_lobby.dart';

// ── Data types ────────────────────────────────────────────────────────────

enum PieceType { king, queen, rook, bishop, knight, pawn }
enum PieceColor { white, black }
enum GameMode { menu, playing }
enum PlayerMode { onePlayer, twoPlayer }

class ChessPiece {
  final PieceType type;
  final PieceColor color;
  bool hasMoved;

  ChessPiece(this.type, this.color, {this.hasMoved = false});

  // Use outlined symbols for white, filled for black
  String get symbol {
    const white = {
      PieceType.king: '\u2654', PieceType.queen: '\u2655',
      PieceType.rook: '\u2656', PieceType.bishop: '\u2657',
      PieceType.knight: '\u2658', PieceType.pawn: '\u2659',
    };
    const black = {
      PieceType.king: '\u265A', PieceType.queen: '\u265B',
      PieceType.rook: '\u265C', PieceType.bishop: '\u265D',
      PieceType.knight: '\u265E', PieceType.pawn: '\u265F',
    };
    return color == PieceColor.white ? white[type]! : black[type]!;
  }

  String get letter {
    const letters = {
      PieceType.king: 'K', PieceType.queen: 'Q',
      PieceType.rook: 'R', PieceType.bishop: 'B',
      PieceType.knight: 'N', PieceType.pawn: '',
    };
    return letters[type]!;
  }

  int get value {
    switch (type) {
      case PieceType.pawn: return 100;
      case PieceType.knight: return 320;
      case PieceType.bishop: return 330;
      case PieceType.rook: return 500;
      case PieceType.queen: return 900;
      case PieceType.king: return 20000;
    }
  }

  ChessPiece copy() => ChessPiece(type, color, hasMoved: hasMoved);
}

// Board color themes
class BoardTheme {
  final String name;
  final Color lightSquare;
  final Color darkSquare;
  final Color whitePiece;
  final Color blackPiece;

  const BoardTheme({
    required this.name,
    required this.lightSquare,
    required this.darkSquare,
    required this.whitePiece,
    required this.blackPiece,
  });
}

const _boardThemes = [
  BoardTheme(
    name: 'Classic',
    lightSquare: Color(0xFFF0D9B5),
    darkSquare: Color(0xFFB58863),
    whitePiece: Color(0xFFFFFFFF),
    blackPiece: Color(0xFF1A1A1A),
  ),
  BoardTheme(
    name: 'Emerald',
    lightSquare: Color(0xFFEEEED2),
    darkSquare: Color(0xFF769656),
    whitePiece: Color(0xFFFFFFFF),
    blackPiece: Color(0xFF1A1A1A),
  ),
  BoardTheme(
    name: 'Midnight',
    lightSquare: Color(0xFFDEE3E6),
    darkSquare: Color(0xFF5D7A99),
    whitePiece: Color(0xFFF0E8D0),
    blackPiece: Color(0xFF2C3E50),
  ),
  BoardTheme(
    name: 'Coral',
    lightSquare: Color(0xFFF5E6CC),
    darkSquare: Color(0xFFD4826A),
    whitePiece: Color(0xFFFFF8F0),
    blackPiece: Color(0xFF3D2B1F),
  ),
  BoardTheme(
    name: 'Royal',
    lightSquare: Color(0xFFE8DAF0),
    darkSquare: Color(0xFF7B5EA7),
    whitePiece: Color(0xFFFFFFFF),
    blackPiece: Color(0xFF1A1A2E),
  ),
];

// ── Main screen ───────────────────────────────────────────────────────────

class ChessGameScreen extends StatefulWidget {
  const ChessGameScreen({super.key});

  @override
  State<ChessGameScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessGameScreen>
    with TickerProviderStateMixin {
  late List<List<ChessPiece?>> _board;
  PieceColor _turn = PieceColor.white;
  (int, int)? _selected;
  List<(int, int)> _validMoves = [];
  bool _gameOver = false;
  String _status = '';
  (int, int)? _lastMoveFrom;
  (int, int)? _lastMoveTo;
  (int, int)? _enPassantTarget;

  GameMode _mode = GameMode.menu;
  PlayerMode _playerMode = PlayerMode.twoPlayer;

  // WiFi multiplayer
  WifiGameService? _wifiService;
  bool _isWifiGame = false;
  bool _showWifiLobby = false;
  PieceColor _humanColor = PieceColor.white;
  int _themeIndex = 0;
  int _pieceStyle = 0; // 0=Classic, 1=Outlined, 2=Minimal
  int _aiDifficulty = 1; // 0=Easy, 1=Medium, 2=Hard
  bool _aiThinking = false;

  // Capture animation
  AnimationController? _captureAnimCtrl;
  (int, int)? _captureSquare;
  PieceColor? _capturedColor;

  // Checkmate celebration
  AnimationController? _checkmateAnimCtrl;
  bool _showCheckmateOverlay = false;

  BoardTheme get _theme => _boardThemes[_themeIndex];

  @override
  void initState() {
    super.initState();
    _initBoard();
  }

  @override
  void dispose() {
    _wifiService?.dispose();
    _captureAnimCtrl?.dispose();
    _checkmateAnimCtrl?.dispose();
    super.dispose();
  }

  void _initBoard() {
    _board = List.generate(8, (_) => List.filled(8, null));
    _turn = PieceColor.white;
    _selected = null;
    _validMoves = [];
    _gameOver = false;
    _enPassantTarget = null;
    _lastMoveFrom = null;
    _lastMoveTo = null;
    _aiThinking = false;
    _showCheckmateOverlay = false;
    _checkmateAnimCtrl?.dispose();
    _checkmateAnimCtrl = null;

    final backRow = [
      PieceType.rook, PieceType.knight, PieceType.bishop,
      PieceType.queen, PieceType.king, PieceType.bishop,
      PieceType.knight, PieceType.rook,
    ];

    for (int c = 0; c < 8; c++) {
      _board[0][c] = ChessPiece(backRow[c], PieceColor.black);
      _board[1][c] = ChessPiece(PieceType.pawn, PieceColor.black);
      _board[6][c] = ChessPiece(PieceType.pawn, PieceColor.white);
      _board[7][c] = ChessPiece(backRow[c], PieceColor.white);
    }

    _status = "White's turn";
  }

  void _startGame(PlayerMode mode, PieceColor humanColor) {
    _initBoard();
    _playerMode = mode;
    _humanColor = humanColor;
    _mode = GameMode.playing;
    setState(() {});

    // If AI plays white, make AI move first
    if (_playerMode == PlayerMode.onePlayer && _humanColor == PieceColor.black) {
      _scheduleAiMove();
    }
  }

  // ── Square tap ──────────────────────────────────────────────────────────

  void _onSquareTap(int r, int c) {
    if (_gameOver || _aiThinking) return;

    // In 1-player mode, ignore taps when it's AI's turn
    if (_playerMode == PlayerMode.onePlayer && _turn != _humanColor) return;
    // In WiFi mode, only allow moves on local player's turn
    if (_isWifiGame && _turn != _humanColor) return;

    final piece = _board[r][c];

    if (_selected != null) {
      if (_validMoves.contains((r, c))) {
        // Send move to opponent over WiFi
        if (_isWifiGame && _wifiService != null) {
          _wifiService!.send({'type': 'move', 'fr': _selected!.$1, 'fc': _selected!.$2, 'tr': r, 'tc': c});
        }
        _makeMove(_selected!.$1, _selected!.$2, r, c);
        return;
      }
      if (piece != null && piece.color == _turn) {
        _selected = (r, c);
        _validMoves = _getLegalMoves(r, c);
        HapticFeedback.selectionClick();
        setState(() {});
        return;
      }
      _selected = null;
      _validMoves = [];
      setState(() {});
      return;
    }

    if (piece != null && piece.color == _turn) {
      _selected = (r, c);
      _validMoves = _getLegalMoves(r, c);
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  void _makeMove(int fromR, int fromC, int toR, int toC) {
    final piece = _board[fromR][fromC]!;
    final captured = _board[toR][toC];

    // Trigger capture animation
    if (captured != null) {
      _triggerCaptureAnim(toR, toC, captured.color);
    }

    // En passant capture
    if (piece.type == PieceType.pawn && _enPassantTarget == (toR, toC)) {
      final captureR = piece.color == PieceColor.white ? toR + 1 : toR - 1;
      _triggerCaptureAnim(captureR, toC, _board[captureR][toC]?.color ?? PieceColor.black);
      _board[captureR][toC] = null;
    }

    // Castling
    if (piece.type == PieceType.king && (fromC - toC).abs() == 2) {
      if (toC == 6) {
        _board[fromR][5] = _board[fromR][7];
        _board[fromR][7] = null;
        _board[fromR][5]?.hasMoved = true;
      } else if (toC == 2) {
        _board[fromR][3] = _board[fromR][0];
        _board[fromR][0] = null;
        _board[fromR][3]?.hasMoved = true;
      }
    }

    // Set en passant target
    _enPassantTarget = null;
    if (piece.type == PieceType.pawn && (fromR - toR).abs() == 2) {
      _enPassantTarget = ((fromR + toR) ~/ 2, fromC);
    }

    // Move piece
    _board[toR][toC] = piece;
    _board[fromR][fromC] = null;
    piece.hasMoved = true;

    // Pawn promotion
    if (piece.type == PieceType.pawn) {
      if ((piece.color == PieceColor.white && toR == 0) ||
          (piece.color == PieceColor.black && toR == 7)) {
        _board[toR][toC] = ChessPiece(PieceType.queen, piece.color, hasMoved: true);
      }
    }

    _lastMoveFrom = (fromR, fromC);
    _lastMoveTo = (toR, toC);
    _selected = null;
    _validMoves = [];

    // Switch turn
    _turn = _turn == PieceColor.white ? PieceColor.black : PieceColor.white;

    // Update status text — wrapped in try-catch so turn always switches
    final name = _turn == PieceColor.white ? 'White' : 'Black';
    _status = "$name's turn";
    try {
      final inCheck = _isKingInCheck(_turn);
      final hasLegal = _hasAnyLegalMoves(_turn);
      if (!hasLegal) {
        _gameOver = true;
        if (inCheck) {
          _status = '${_turn == PieceColor.white ? "Black" : "White"} wins by checkmate!';
          _triggerCheckmateOverlay();
        } else {
          _status = 'Stalemate — Draw!';
        }
      } else if (inCheck) {
        _status = '$name is in check!';
      }
    } catch (_) {
      // If check detection fails, game continues with turn switched
    }

    HapticFeedback.mediumImpact();
    setState(() {});

    // Schedule AI move if needed
    if (!_gameOver &&
        _playerMode == PlayerMode.onePlayer &&
        _turn != _humanColor) {
      _scheduleAiMove();
    }
  }

  // ── AI ──────────────────────────────────────────────────────────────────

  void _scheduleAiMove() {
    _aiThinking = true;
    setState(() {});

    final delay = _aiDifficulty == 2 ? 100 : 400;
    Future.delayed(Duration(milliseconds: delay), () {
      if (!mounted || _gameOver) return;
      try {
        final move = _findBestMove();
        if (move != null) {
          _makeMove(move.$1, move.$2, move.$3, move.$4);
        }
      } catch (_) {
        // Fallback: play any legal move
        final moves = _getAllMoves(
          _humanColor == PieceColor.white ? PieceColor.black : PieceColor.white,
        );
        if (moves.isNotEmpty) {
          final m = moves[math.Random().nextInt(moves.length)];
          _makeMove(m.$1, m.$2, m.$3, m.$4);
        }
      }
      _aiThinking = false;
      if (mounted) setState(() {});
    });
  }

  // ── Piece-square tables (from white's perspective, row 0 = rank 8) ─────

  static const _pawnTable = [
     0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0,
  ];

  static const _knightTable = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50,
  ];

  static const _bishopTable = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20,
  ];

  static const _rookTable = [
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
     0,  0,  0,  5,  5,  0,  0,  0,
  ];

  static const _queenTable = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20,
  ];

  static const _kingMiddleTable = [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20,
  ];

  int _getPieceSquareValue(PieceType type, PieceColor color, int r, int c) {
    final table = switch (type) {
      PieceType.pawn   => _pawnTable,
      PieceType.knight => _knightTable,
      PieceType.bishop => _bishopTable,
      PieceType.rook   => _rookTable,
      PieceType.queen  => _queenTable,
      PieceType.king   => _kingMiddleTable,
    };
    // For white, use the table as-is; for black, mirror vertically
    final row = color == PieceColor.white ? r : 7 - r;
    return table[row * 8 + c];
  }

  /// Full board evaluation from the perspective of [color].
  int _evaluateBoard(PieceColor color) {
    int score = 0;
    final opponent = color == PieceColor.white ? PieceColor.black : PieceColor.white;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = _board[r][c];
        if (p == null) continue;
        final material = p.value;
        final positional = _getPieceSquareValue(p.type, p.color, r, c);
        if (p.color == color) {
          score += material + positional;
        } else {
          score -= material + positional;
        }
      }
    }

    // Mobility bonus
    final myMoves = _getAllMoves(color).length;
    final oppMoves = _getAllMoves(opponent).length;
    score += (myMoves - oppMoves) * 5;

    return score;
  }

  /// Simulate a move on the board, returning undo info.
  _UndoInfo _doMove(int fr, int fc, int tr, int tc) {
    final piece = _board[fr][fc]!;
    final captured = _board[tr][tc];
    final savedEP = _enPassantTarget;
    final savedHasMoved = piece.hasMoved;

    ChessPiece? epCaptured;
    int epRow = -1;
    if (piece.type == PieceType.pawn && _enPassantTarget == (tr, tc)) {
      epRow = piece.color == PieceColor.white ? tr + 1 : tr - 1;
      epCaptured = _board[epRow][tc];
      _board[epRow][tc] = null;
    }

    // Castling rook move
    int castleRookFromC = -1, castleRookToC = -1;
    if (piece.type == PieceType.king && (fc - tc).abs() == 2) {
      if (tc == 6) { castleRookFromC = 7; castleRookToC = 5; }
      else if (tc == 2) { castleRookFromC = 0; castleRookToC = 3; }
      if (castleRookFromC >= 0) {
        _board[fr][castleRookToC] = _board[fr][castleRookFromC];
        _board[fr][castleRookFromC] = null;
        _board[fr][castleRookToC]?.hasMoved = true;
      }
    }

    _board[tr][tc] = piece;
    _board[fr][fc] = null;
    piece.hasMoved = true;

    // En passant target
    _enPassantTarget = null;
    if (piece.type == PieceType.pawn && (fr - tr).abs() == 2) {
      _enPassantTarget = ((fr + tr) ~/ 2, fc);
    }

    // Pawn promotion to queen
    ChessPiece? promotedFrom;
    if (piece.type == PieceType.pawn &&
        ((piece.color == PieceColor.white && tr == 0) ||
         (piece.color == PieceColor.black && tr == 7))) {
      promotedFrom = piece;
      _board[tr][tc] = ChessPiece(PieceType.queen, piece.color, hasMoved: true);
    }

    return _UndoInfo(
      fr: fr, fc: fc, tr: tr, tc: tc,
      piece: piece, captured: captured,
      savedEP: savedEP, savedHasMoved: savedHasMoved,
      epCaptured: epCaptured, epRow: epRow,
      castleRookFromC: castleRookFromC, castleRookToC: castleRookToC,
      row: fr, promotedFrom: promotedFrom,
    );
  }

  void _undoMove(_UndoInfo u) {
    // Undo promotion
    if (u.promotedFrom != null) {
      _board[u.tr][u.tc] = u.promotedFrom;
    }

    _board[u.fr][u.fc] = u.piece;
    _board[u.tr][u.tc] = u.captured;
    u.piece.hasMoved = u.savedHasMoved;
    _enPassantTarget = u.savedEP;

    if (u.epCaptured != null) {
      _board[u.epRow][u.tc] = u.epCaptured;
    }

    // Undo castling rook
    if (u.castleRookFromC >= 0) {
      _board[u.row][u.castleRookFromC] = _board[u.row][u.castleRookToC];
      _board[u.row][u.castleRookToC] = null;
      _board[u.row][u.castleRookFromC]?.hasMoved = false;
    }
  }

  /// Minimax with alpha-beta pruning.
  int _minimax(int depth, int alpha, int beta, bool isMaximizing, PieceColor aiColor) {
    final opponent = aiColor == PieceColor.white ? PieceColor.black : PieceColor.white;

    if (depth == 0) {
      return _evaluateBoard(aiColor);
    }

    final currentColor = isMaximizing ? aiColor : opponent;
    final moves = _getAllMoves(currentColor);

    if (moves.isEmpty) {
      if (_isKingInCheck(currentColor)) {
        // Checkmate — worse the closer it is (prefer faster mates)
        return isMaximizing ? -100000 - depth : 100000 + depth;
      }
      return 0; // Stalemate
    }

    if (isMaximizing) {
      int maxEval = -999999;
      for (final (fr, fc, tr, tc) in moves) {
        final undo = _doMove(fr, fc, tr, tc);
        final eval = _minimax(depth - 1, alpha, beta, false, aiColor);
        _undoMove(undo);
        maxEval = math.max(maxEval, eval);
        alpha = math.max(alpha, eval);
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      int minEval = 999999;
      for (final (fr, fc, tr, tc) in moves) {
        final undo = _doMove(fr, fc, tr, tc);
        final eval = _minimax(depth - 1, alpha, beta, true, aiColor);
        _undoMove(undo);
        minEval = math.min(minEval, eval);
        beta = math.min(beta, eval);
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  (int, int, int, int)? _findBestMove() {
    final aiColor = _humanColor == PieceColor.white ? PieceColor.black : PieceColor.white;
    final moves = _getAllMoves(aiColor);
    if (moves.isEmpty) return null;

    // Shuffle for variety
    final rng = math.Random();
    moves.shuffle(rng);

    int bestScore = -999999;
    (int, int, int, int)? bestMove;

    if (_aiDifficulty == 0) {
      // Easy: single-ply scoring with random noise
      for (final (fr, fc, tr, tc) in moves) {
        final score = _scoreMoveSinglePly(fr, fc, tr, tc, aiColor) + rng.nextInt(51);
        if (score > bestScore) {
          bestScore = score;
          bestMove = (fr, fc, tr, tc);
        }
      }
    } else {
      // Medium: depth 2, Hard: depth 4
      final depth = _aiDifficulty == 1 ? 2 : 4;
      for (final (fr, fc, tr, tc) in moves) {
        final undo = _doMove(fr, fc, tr, tc);
        final score = _minimax(depth - 1, -999999, 999999, false, aiColor);
        _undoMove(undo);
        if (score > bestScore) {
          bestScore = score;
          bestMove = (fr, fc, tr, tc);
        }
      }
    }

    return bestMove;
  }

  /// Original single-ply scoring used by Easy difficulty.
  int _scoreMoveSinglePly(int fr, int fc, int tr, int tc, PieceColor aiColor) {
    int score = 0;
    final piece = _board[fr][fc]!;
    final target = _board[tr][tc];

    // Capture value
    if (target != null) {
      score += target.value * 10;
      score -= piece.value;
    }

    // Simulate move
    final savedTo = _board[tr][tc];
    final savedEP = _enPassantTarget;
    final savedHasMoved = piece.hasMoved;
    _board[tr][tc] = piece;
    _board[fr][fc] = null;
    piece.hasMoved = true;

    ChessPiece? epCaptured;
    int epRow = -1;
    if (piece.type == PieceType.pawn && _enPassantTarget == (tr, tc)) {
      epRow = piece.color == PieceColor.white ? tr + 1 : tr - 1;
      epCaptured = _board[epRow][tc];
      _board[epRow][tc] = null;
      score += 100;
    }

    _enPassantTarget = null;
    if (piece.type == PieceType.pawn && (fr - tr).abs() == 2) {
      _enPassantTarget = ((fr + tr) ~/ 2, fc);
    }

    final opponent = aiColor == PieceColor.white ? PieceColor.black : PieceColor.white;
    if (_isKingInCheck(opponent)) {
      score += 500;
      if (!_hasAnyLegalMoves(opponent)) {
        score += 50000;
      }
    }

    // Positional bonuses
    if (piece.type == PieceType.pawn) {
      final advance = piece.color == PieceColor.white ? (6 - tr) : (tr - 1);
      score += advance * 15;
      if (tc >= 3 && tc <= 4) score += 20;
    } else if (piece.type == PieceType.knight || piece.type == PieceType.bishop) {
      if (tr >= 2 && tr <= 5 && tc >= 2 && tc <= 5) score += 30;
    } else if (piece.type == PieceType.king && (fc - tc).abs() == 2) {
      score += 60;
    }

    if (_isSquareAttacked(tr, tc, aiColor)) {
      score -= piece.value ~/ 2;
    }

    // Undo
    _board[fr][fc] = piece;
    _board[tr][tc] = savedTo;
    piece.hasMoved = savedHasMoved;
    _enPassantTarget = savedEP;
    if (epCaptured != null) _board[epRow][tc] = epCaptured;

    return score;
  }

  List<(int, int, int, int)> _getAllMoves(PieceColor color) {
    final moves = <(int, int, int, int)>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = _board[r][c];
        if (p != null && p.color == color) {
          for (final (tr, tc) in _getLegalMoves(r, c)) {
            moves.add((r, c, tr, tc));
          }
        }
      }
    }
    return moves;
  }

  // ── Move generation ─────────────────────────────────────────────────────

  List<(int, int)> _getLegalMoves(int r, int c) {
    final piece = _board[r][c];
    if (piece == null) return [];

    final pseudo = _getPseudoMoves(r, c, piece);
    return pseudo.where((move) {
      return !_wouldBeInCheck(r, c, move.$1, move.$2, piece.color);
    }).toList();
  }

  List<(int, int)> _getPseudoMoves(int r, int c, ChessPiece piece) {
    switch (piece.type) {
      case PieceType.pawn:   return _pawnMoves(r, c, piece);
      case PieceType.knight: return _knightMoves(r, c, piece);
      case PieceType.bishop: return _slidingMoves(r, c, piece, [(1,1),(1,-1),(-1,1),(-1,-1)]);
      case PieceType.rook:   return _slidingMoves(r, c, piece, [(0,1),(0,-1),(1,0),(-1,0)]);
      case PieceType.queen:  return _slidingMoves(r, c, piece, [(0,1),(0,-1),(1,0),(-1,0),(1,1),(1,-1),(-1,1),(-1,-1)]);
      case PieceType.king:   return _kingMoves(r, c, piece);
    }
  }

  List<(int, int)> _pawnMoves(int r, int c, ChessPiece p) {
    final moves = <(int, int)>[];
    final dir = p.color == PieceColor.white ? -1 : 1;
    final startRow = p.color == PieceColor.white ? 6 : 1;

    if (_inBounds(r + dir, c) && _board[r + dir][c] == null) {
      moves.add((r + dir, c));
      if (r == startRow && _board[r + 2 * dir][c] == null) {
        moves.add((r + 2 * dir, c));
      }
    }
    for (final dc in [-1, 1]) {
      final nr = r + dir, nc = c + dc;
      if (!_inBounds(nr, nc)) continue;
      if (_board[nr][nc] != null && _board[nr][nc]!.color != p.color) {
        moves.add((nr, nc));
      }
      if (_enPassantTarget == (nr, nc)) {
        moves.add((nr, nc));
      }
    }
    return moves;
  }

  List<(int, int)> _knightMoves(int r, int c, ChessPiece p) {
    const offsets = [(-2,-1),(-2,1),(-1,-2),(-1,2),(1,-2),(1,2),(2,-1),(2,1)];
    return offsets
        .map((d) => (r + d.$1, c + d.$2))
        .where((s) => _inBounds(s.$1, s.$2) &&
            (_board[s.$1][s.$2] == null || _board[s.$1][s.$2]!.color != p.color))
        .toList();
  }

  List<(int, int)> _slidingMoves(int r, int c, ChessPiece p, List<(int, int)> dirs) {
    final moves = <(int, int)>[];
    for (final (dr, dc) in dirs) {
      var nr = r + dr, nc = c + dc;
      while (_inBounds(nr, nc)) {
        if (_board[nr][nc] == null) {
          moves.add((nr, nc));
        } else {
          if (_board[nr][nc]!.color != p.color) moves.add((nr, nc));
          break;
        }
        nr += dr; nc += dc;
      }
    }
    return moves;
  }

  List<(int, int)> _kingMoves(int r, int c, ChessPiece p) {
    final moves = <(int, int)>[];
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (_inBounds(nr, nc) &&
            (_board[nr][nc] == null || _board[nr][nc]!.color != p.color)) {
          moves.add((nr, nc));
        }
      }
    }
    // Castling
    if (!p.hasMoved && !_isKingInCheck(p.color)) {
      // Kingside
      if (_board[r][7]?.type == PieceType.rook && _board[r][7]?.hasMoved == false) {
        if (_board[r][5] == null && _board[r][6] == null) {
          if (!_isSquareAttacked(r, 5, p.color) && !_isSquareAttacked(r, 6, p.color)) {
            moves.add((r, 6));
          }
        }
      }
      // Queenside
      if (_board[r][0]?.type == PieceType.rook && _board[r][0]?.hasMoved == false) {
        if (_board[r][1] == null && _board[r][2] == null && _board[r][3] == null) {
          if (!_isSquareAttacked(r, 2, p.color) && !_isSquareAttacked(r, 3, p.color)) {
            moves.add((r, 2));
          }
        }
      }
    }
    return moves;
  }

  bool _inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  bool _isSquareAttacked(int r, int c, PieceColor byDefender) {
    final attacker = byDefender == PieceColor.white ? PieceColor.black : PieceColor.white;
    for (int rr = 0; rr < 8; rr++) {
      for (int cc = 0; cc < 8; cc++) {
        final p = _board[rr][cc];
        if (p != null && p.color == attacker) {
          // Use attack-only moves (no castling) to avoid circular recursion
          final moves = p.type == PieceType.king
              ? _kingAttacks(rr, cc, p)
              : _getPseudoMoves(rr, cc, p);
          if (moves.contains((r, c))) return true;
        }
      }
    }
    return false;
  }

  /// King attack squares only (no castling) — used to prevent recursion
  List<(int, int)> _kingAttacks(int r, int c, ChessPiece p) {
    final moves = <(int, int)>[];
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (_inBounds(nr, nc) &&
            (_board[nr][nc] == null || _board[nr][nc]!.color != p.color)) {
          moves.add((nr, nc));
        }
      }
    }
    return moves;
  }

  bool _isKingInCheck(PieceColor color) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = _board[r][c];
        if (p != null && p.type == PieceType.king && p.color == color) {
          return _isSquareAttacked(r, c, color);
        }
      }
    }
    return false;
  }

  bool _wouldBeInCheck(int fromR, int fromC, int toR, int toC, PieceColor color) {
    final piece = _board[fromR][fromC]!;
    final savedTo = _board[toR][toC];
    final savedEP = _enPassantTarget;

    // Handle en passant capture in simulation
    ChessPiece? epCaptured;
    int epRow = -1;
    if (piece.type == PieceType.pawn && _enPassantTarget == (toR, toC)) {
      epRow = piece.color == PieceColor.white ? toR + 1 : toR - 1;
      epCaptured = _board[epRow][toC];
      _board[epRow][toC] = null;
    }

    _board[toR][toC] = piece;
    _board[fromR][fromC] = null;

    final inCheck = _isKingInCheck(color);

    // Undo
    _board[fromR][fromC] = piece;
    _board[toR][toC] = savedTo;
    _enPassantTarget = savedEP;
    if (epCaptured != null) {
      _board[epRow][toC] = epCaptured;
    }

    return inCheck;
  }

  bool _hasAnyLegalMoves(PieceColor color) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = _board[r][c];
        if (p != null && p.color == color) {
          if (_getLegalMoves(r, c).isNotEmpty) return true;
        }
      }
    }
    return false;
  }

  // ── WiFi ─────────────────────────────────────────────────────────────────

  void _startWifiGame(WifiGameService service) {
    _wifiService = service;
    _isWifiGame = true;
    _showWifiLobby = false;
    _initBoard();
    // Host plays white, client plays black
    _humanColor = service.isHost ? PieceColor.white : PieceColor.black;
    _playerMode = PlayerMode.twoPlayer;
    _mode = GameMode.playing;

    _wifiService!.onMessage = (msg) {
      if (!mounted) return;
      final type = msg['type'] as String? ?? '';
      if (type == 'move') {
        final fr = msg['fr'] as int;
        final fc = msg['fc'] as int;
        final tr = msg['tr'] as int;
        final tc = msg['tc'] as int;
        if (!_gameOver) {
          _makeMove(fr, fc, tr, tc);
        }
      }
    };
    _wifiService!.onDisconnected = () {
      if (!mounted) return;
      _wifiService = null;
      _isWifiGame = false;
      setState(() => _mode = GameMode.menu);
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

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showWifiLobby) {
      return WifiLobby(
        gameName: 'Chess',
        maxPlayers: 2,
        onGameStart: _startWifiGame,
        onBack: () => setState(() => _showWifiLobby = false),
      );
    }
    if (_mode == GameMode.menu) return _buildMenu();
    return _buildGame();
  }

  // ── Pre-game menu ───────────────────────────────────────────────────────

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Chess'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Chess'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Text('\u265A', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 8),
              const Text('Chess',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                      color: GameTheme.textPrimary)),
              const SizedBox(height: 40),

              // 1 Player
              _menuButton(
                icon: Icons.smart_toy_rounded,
                label: '1 Player',
                subtitle: 'Play against AI',
                onTap: () => _showColorPicker(PlayerMode.onePlayer),
              ),
              const SizedBox(height: 16),

              // 2 Player
              _menuButton(
                icon: Icons.people_rounded,
                label: '2 Players',
                subtitle: 'Local multiplayer',
                onTap: () => _showColorPicker(PlayerMode.twoPlayer),
              ),
              const SizedBox(height: 16),

              // WiFi Multiplayer
              _menuButton(
                icon: Icons.wifi_rounded,
                label: 'WiFi Multiplayer',
                subtitle: 'Play over WiFi',
                onTap: () => setState(() => _showWifiLobby = true),
              ),

              const SizedBox(height: 40),

              // Board theme selector
              const Text('Board Theme',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: GameTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  itemCount: _boardThemes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _themeChip(i),
                ),
              ),

              const SizedBox(height: 28),

              // Piece style selector
              const Text('Piece Style',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: GameTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pieceStyleChip(0, '\u265A', 'Classic'),
                  const SizedBox(width: 10),
                  _pieceStyleChip(1, '\u2654', 'Outlined'),
                  const SizedBox(width: 10),
                  _pieceStyleChip(2, 'K', 'Minimal'),
                ],
              ),

              const SizedBox(height: 24),
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
                Text(label,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                        color: GameTheme.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(fontSize: 13, color: GameTheme.textSecondary)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: GameTheme.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _themeChip(int index) {
    final t = _boardThemes[index];
    final selected = _themeIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _themeIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? GameTheme.accent.withValues(alpha: 0.15) : GameTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? GameTheme.accent : GameTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini board preview
            SizedBox(
              width: 24, height: 24,
              child: GridView.count(
                crossAxisCount: 2,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  Container(color: t.lightSquare),
                  Container(color: t.darkSquare),
                  Container(color: t.darkSquare),
                  Container(color: t.lightSquare),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(t.name,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: selected ? GameTheme.accent : GameTheme.textSecondary,
                )),
          ],
        ),
      ),
    );
  }

  Widget _pieceStyleChip(int index, String symbol, String label) {
    final selected = _pieceStyle == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _pieceStyle = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? GameTheme.accent.withValues(alpha: 0.15) : GameTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? GameTheme.accent : GameTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(symbol, style: TextStyle(fontSize: 22,
              color: selected ? GameTheme.textPrimary : GameTheme.textSecondary)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: selected ? GameTheme.accent : GameTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(PlayerMode mode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: GameTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: GameTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Difficulty selector (1-player only)
              if (mode == PlayerMode.onePlayer) ...[
                const Text('AI DIFFICULTY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: GameTheme.textSecondary, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: _difficultyButton(i, setSheetState)),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
              ],

              Text(
                'Choose your side',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                    color: GameTheme.textPrimary),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _colorOption(PieceColor.white, mode)),
                  const SizedBox(width: 16),
                  Expanded(child: _colorOption(PieceColor.black, mode)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _difficultyButton(int level, void Function(void Function()) setSheetState) {
    const labels = ['Easy', 'Medium', 'Hard'];
    const icons = [Icons.sentiment_satisfied_rounded, Icons.psychology_rounded, Icons.local_fire_department_rounded];
    final selected = _aiDifficulty == level;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _aiDifficulty = level);
        setSheetState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? GameTheme.accent.withValues(alpha: 0.15) : GameTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? GameTheme.accent : GameTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icons[level], size: 22,
                color: selected ? GameTheme.accent : GameTheme.textSecondary),
            const SizedBox(height: 4),
            Text(labels[level],
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: selected ? GameTheme.accent : GameTheme.textSecondary,
                )),
          ],
        ),
      ),
    );
  }

  Widget _colorOption(PieceColor color, PlayerMode mode) {
    final isWhite = color == PieceColor.white;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
        _startGame(mode, color);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isWhite ? Colors.white : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border),
        ),
        child: Column(
          children: [
            Text(
              isWhite ? '\u2654' : '\u265A',
              style: TextStyle(fontSize: 48, color: isWhite ? Colors.black : Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              isWhite ? 'White' : 'Black',
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: isWhite ? Colors.black : Colors.white,
              ),
            ),
            Text(
              isWhite ? 'Moves first' : 'Moves second',
              style: TextStyle(
                fontSize: 12,
                color: isWhite ? Colors.black54 : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Game UI ─────────────────────────────────────────────────────────────

  Widget _buildGame() {
    final screenW = MediaQuery.of(context).size.width;
    final boardSize = screenW - 12;
    final cellSize = boardSize / 8;

    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: Text(_isWifiGame ? 'Chess — WiFi'
            : _playerMode == PlayerMode.onePlayer
            ? 'Chess — vs AI (${['Easy', 'Medium', 'Hard'][_aiDifficulty]})'
            : 'Chess — 2 Players'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () {
            _disposeWifi();
            setState(() {
              _mode = GameMode.menu;
              _showCheckmateOverlay = false;
            });
          },
        ),
        actions: [
          // Theme switcher
          IconButton(
            icon: const Icon(Icons.palette_outlined, color: GameTheme.textSecondary),
            onPressed: () {
              setState(() => _themeIndex = (_themeIndex + 1) % _boardThemes.length);
              HapticFeedback.selectionClick();
            },
            tooltip: 'Change board theme',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
            onPressed: () {
              _initBoard();
              setState(() {});
              if (_playerMode == PlayerMode.onePlayer && _humanColor == PieceColor.black) {
                _scheduleAiMove();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          // Status
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_aiThinking) ...[
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: GameTheme.accent),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  _aiThinking ? 'AI is thinking...' : _status,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _status.contains('check') ? GameTheme.accentAlt : GameTheme.accent,
                  ),
                ),
              ],
            ),
          ),

          // Turn indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _turnIndicator(PieceColor.white),
              const SizedBox(width: 20),
              _turnIndicator(PieceColor.black),
            ],
          ),

          const SizedBox(height: 12),

          // Board theme name
          Text(_theme.name,
              style: const TextStyle(fontSize: 11, color: GameTheme.textSecondary,
                  letterSpacing: 1)),
          const SizedBox(height: 6),

          // Board
          Container(
            width: boardSize,
            height: boardSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  for (int r = 0; r < 8; r++)
                    for (int c = 0; c < 8; c++)
                      Positioned(
                        left: c * cellSize,
                        top: r * cellSize,
                        child: GestureDetector(
                          onTap: () => _onSquareTap(r, c),
                          child: _buildSquare(r, c, cellSize),
                        ),
                      ),
                ],
              ),
            ),
          ),

          const Spacer(),

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
                      if (_playerMode == PlayerMode.onePlayer && _humanColor == PieceColor.black) {
                        _scheduleAiMove();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GameTheme.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Rematch',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => setState(() => _mode = GameMode.menu),
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

          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              'Tap a piece to select, then tap where to move',
              style: TextStyle(color: GameTheme.textSecondary.withValues(alpha: 0.5), fontSize: 12),
            ),
          ),
        ],
      ),

          // Checkmate celebration overlay
          if (_showCheckmateOverlay && _checkmateAnimCtrl != null)
            _buildCheckmateOverlay(),
        ],
      ),
    );
  }

  Widget _buildCheckmateOverlay() {
    final winner = _turn == PieceColor.white ? PieceColor.black : PieceColor.white;
    final winnerName = winner == PieceColor.white ? 'White' : 'Black';
    final kingSymbol = winner == PieceColor.white ? '\u2654' : '\u265A';

    return AnimatedBuilder(
      animation: _checkmateAnimCtrl!,
      builder: (_, __) {
        final t = Curves.elasticOut.transform(
          _checkmateAnimCtrl!.value.clamp(0.0, 1.0),
        );
        final opacity = _checkmateAnimCtrl!.value.clamp(0.0, 1.0);

        return Container(
          color: Colors.black.withValues(alpha: opacity * 0.7),
          child: Center(
            child: Transform.scale(
              scale: t,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                decoration: BoxDecoration(
                  color: GameTheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: GameTheme.gold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: GameTheme.gold.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events_rounded,
                        color: GameTheme.gold, size: 48),
                    const SizedBox(height: 12),
                    const Text('Checkmate!',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                            color: GameTheme.gold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(kingSymbol, style: const TextStyle(fontSize: 56)),
                    const SizedBox(height: 8),
                    Text('$winnerName wins!',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                            color: GameTheme.textPrimary)),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            _initBoard();
                            setState(() {});
                            if (_playerMode == PlayerMode.onePlayer &&
                                _humanColor == PieceColor.black) {
                              _scheduleAiMove();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GameTheme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Play Again',
                              style: TextStyle(fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _mode = GameMode.menu;
                            _showCheckmateOverlay = false;
                          }),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: GameTheme.accent),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Menu',
                              style: TextStyle(fontWeight: FontWeight.w700,
                                  color: GameTheme.accent)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _turnIndicator(PieceColor color) {
    final active = _turn == color && !_gameOver;
    final isWhite = color == PieceColor.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? GameTheme.accent.withValues(alpha: 0.15) : GameTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? GameTheme.accent : GameTheme.border,
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: isWhite ? _theme.whitePiece : _theme.blackPiece,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey, width: 1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isWhite ? 'White' : 'Black',
            style: TextStyle(
              color: active ? GameTheme.accent : GameTheme.textSecondary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
          if (_playerMode == PlayerMode.onePlayer) ...[
            const SizedBox(width: 4),
            Text(
              color == _humanColor ? '(You)' : '(AI)',
              style: TextStyle(
                fontSize: 11,
                color: active ? GameTheme.accent.withValues(alpha: 0.6) : GameTheme.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _triggerCaptureAnim(int r, int c, PieceColor color) {
    _captureAnimCtrl?.dispose();
    _captureAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _captureSquare = (r, c);
    _capturedColor = color;
    _captureAnimCtrl!.forward().then((_) {
      if (mounted) {
        setState(() {
          _captureSquare = null;
          _capturedColor = null;
        });
      }
    });
  }

  void _triggerCheckmateOverlay() {
    _checkmateAnimCtrl?.dispose();
    _checkmateAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _showCheckmateOverlay = true;
    _checkmateAnimCtrl!.forward();
  }

  Widget _buildSquare(int r, int c, double size) {
    final isLight = (r + c) % 2 == 0;
    final piece = _board[r][c];
    final isSelected = _selected == (r, c);
    final isValidMove = _validMoves.contains((r, c));
    final isLastMove = _lastMoveFrom == (r, c) || _lastMoveTo == (r, c);
    final isCapturing = _captureSquare == (r, c);

    Color bgColor;
    if (isSelected) {
      bgColor = const Color(0xFF66BB6A);
    } else if (isLastMove) {
      bgColor = isLight ? const Color(0xFFF7F78A) : const Color(0xFFDADA58);
    } else {
      bgColor = isLight ? _theme.lightSquare : _theme.darkSquare;
    }

    return Container(
      width: size,
      height: size,
      color: bgColor,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Valid move indicator
          if (isValidMove)
            piece != null
                ? Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xCCFF4444), width: 3),
                      color: const Color(0x33FF4444),
                    ),
                  )
                : Container(
                    width: size * 0.32,
                    height: size * 0.32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x8844AA44),
                    ),
                  ),

          // Capture burst animation
          if (isCapturing && _captureAnimCtrl != null)
            AnimatedBuilder(
              animation: _captureAnimCtrl!,
              builder: (_, __) {
                final t = _captureAnimCtrl!.value;
                return CustomPaint(
                  size: Size(size, size),
                  painter: _CaptureBurstPainter(
                    progress: t,
                    color: _capturedColor == PieceColor.white
                        ? _theme.whitePiece
                        : _theme.blackPiece,
                  ),
                );
              },
            ),

          // Piece
          if (piece != null)
            _buildPiece(piece, size),
        ],
      ),
    );
  }

  Widget _buildPiece(ChessPiece piece, double size) {
    final isWhite = piece.color == PieceColor.white;

    // Gradient colors for premium look
    final gradientColors = isWhite
        ? [_theme.whitePiece, Color.lerp(_theme.whitePiece, Colors.grey.shade300, 0.3)!]
        : [Color.lerp(_theme.blackPiece, Colors.grey.shade700, 0.2)!, _theme.blackPiece];
    final fgColor = isWhite ? _theme.blackPiece : _theme.whitePiece;
    final borderColor = isWhite
        ? Colors.black.withValues(alpha: 0.25)
        : Colors.white.withValues(alpha: 0.15);
    final glowColor = isWhite
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.3);

    // Piece style sets: Classic (filled), Outlined, Minimal (letters)
    const _pieceStyleSets = [
      // Classic (filled Unicode)
      {
        PieceType.king: '\u265A',
        PieceType.queen: '\u265B',
        PieceType.rook: '\u265C',
        PieceType.bishop: '\u265D',
        PieceType.knight: '\u265E',
        PieceType.pawn: '\u265F',
      },
      // Outlined (white Unicode)
      {
        PieceType.king: '\u2654',
        PieceType.queen: '\u2655',
        PieceType.rook: '\u2656',
        PieceType.bishop: '\u2657',
        PieceType.knight: '\u2658',
        PieceType.pawn: '\u2659',
      },
      // Minimal (letter-based)
      {
        PieceType.king: 'K',
        PieceType.queen: 'Q',
        PieceType.rook: 'R',
        PieceType.bishop: 'B',
        PieceType.knight: 'N',
        PieceType.pawn: 'P',
      },
    ];
    final pieceSymbols = _pieceStyleSets[_pieceStyle];

    return Container(
      width: size * 0.82,
      height: size * 0.82,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          // Drop shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
          // Inner glow effect
          BoxShadow(
            color: glowColor,
            blurRadius: 2,
            spreadRadius: -1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          pieceSymbols[piece.type]!,
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w900,
            color: fgColor,
            height: 1.0,
            shadows: [
              Shadow(
                color: fgColor.withValues(alpha: 0.3),
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Undo info for simulating moves in minimax.
class _UndoInfo {
  final int fr, fc, tr, tc;
  final ChessPiece piece;
  final ChessPiece? captured;
  final (int, int)? savedEP;
  final bool savedHasMoved;
  final ChessPiece? epCaptured;
  final int epRow;
  final int castleRookFromC, castleRookToC;
  final int row;
  final ChessPiece? promotedFrom;

  _UndoInfo({
    required this.fr, required this.fc,
    required this.tr, required this.tc,
    required this.piece, required this.captured,
    required this.savedEP, required this.savedHasMoved,
    required this.epCaptured, required this.epRow,
    required this.castleRookFromC, required this.castleRookToC,
    required this.row, required this.promotedFrom,
  });
}

/// Particle burst effect when a piece is captured
class _CaptureBurstPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CaptureBurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.8;
    final rng = math.Random(42); // Fixed seed for consistent pattern

    // Ring burst
    final ringPaint = Paint()
      ..color = color.withValues(alpha: (1 - progress) * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * (1 - progress);
    canvas.drawCircle(center, maxRadius * progress, ringPaint);

    // Particles flying outward
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi + rng.nextDouble() * 0.5;
      final dist = maxRadius * progress * (0.5 + rng.nextDouble() * 0.5);
      final particleSize = (1 - progress) * (2 + rng.nextDouble() * 3);
      final px = center.dx + math.cos(angle) * dist;
      final py = center.dy + math.sin(angle) * dist;

      final pPaint = Paint()
        ..color = Color.lerp(
          color,
          const Color(0xFFFF6B6B),
          rng.nextDouble() * 0.5,
        )!.withValues(alpha: (1 - progress) * 0.8);

      canvas.drawCircle(Offset(px, py), particleSize, pPaint);
    }

    // Center flash
    if (progress < 0.3) {
      final flashPaint = Paint()
        ..color = Colors.white.withValues(alpha: (1 - progress / 0.3) * 0.7);
      canvas.drawCircle(center, size.width * 0.3 * (1 - progress / 0.3), flashPaint);
    }
  }

  @override
  bool shouldRepaint(_CaptureBurstPainter old) => old.progress != progress;
}
