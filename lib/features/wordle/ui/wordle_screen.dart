import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../data/word_list.dart';

enum TileState { empty, filled, correct, present, absent }

class WordleScreen extends StatefulWidget {
  const WordleScreen({super.key});
  @override
  State<WordleScreen> createState() => _WordleScreenState();
}

class _WordleScreenState extends State<WordleScreen> with TickerProviderStateMixin {
  static const int _maxGuesses = 6;
  static const int _wordLength = 5;

  late String _answer;
  List<String> _guesses = [];
  String _currentGuess = '';
  bool _gameOver = false;
  bool _won = false;
  String _message = '';
  int _hintsUsed = 0;
  static const int _maxHints = 2;
  final Set<int> _revealedPositions = {};
  int _streak = 0;
  int _bestStreak = 0;
  int _gamesPlayed = 0;
  int _gamesWon = 0;

  // Keyboard state
  final Map<String, TileState> _keyStates = {};

  // Animations
  AnimationController? _shakeCtrl;
  AnimationController? _bounceCtrl;
  final List<AnimationController> _flipControllers = [];

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _bounceCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _loadStats();
    _newGame();
  }

  @override
  void dispose() {
    _shakeCtrl?.dispose();
    _bounceCtrl?.dispose();
    for (final c in _flipControllers) { c.dispose(); }
    super.dispose();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _streak = prefs.getInt('wordle_streak') ?? 0;
      _bestStreak = prefs.getInt('wordle_best_streak') ?? 0;
      _gamesPlayed = prefs.getInt('wordle_played') ?? 0;
      _gamesWon = prefs.getInt('wordle_won') ?? 0;
    });
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wordle_streak', _streak);
    await prefs.setInt('wordle_best_streak', _bestStreak);
    await prefs.setInt('wordle_played', _gamesPlayed);
    await prefs.setInt('wordle_won', _gamesWon);
  }

  void _newGame() {
    final rng = Random();
    _answer = wordleAnswers[rng.nextInt(wordleAnswers.length)].toUpperCase();
    _guesses = [];
    _currentGuess = '';
    _gameOver = false;
    _hintsUsed = 0;
    _revealedPositions.clear();
    _won = false;
    _message = '';
    _keyStates.clear();
    for (final c in _flipControllers) { c.dispose(); }
    _flipControllers.clear();
    setState(() {});
  }

  void _onKey(String key) {
    if (_gameOver) return;

    if (key == 'ENTER') {
      _submitGuess();
    } else if (key == '⌫') {
      if (_currentGuess.isNotEmpty) {
        setState(() => _currentGuess = _currentGuess.substring(0, _currentGuess.length - 1));
      }
    } else if (_currentGuess.length < _wordLength) {
      setState(() => _currentGuess += key);
      HapticFeedback.selectionClick();
    }
  }

  void _submitGuess() {
    if (_currentGuess.length != _wordLength) {
      _shake('Not enough letters');
      return;
    }

    // Check if valid word
    if (!wordleAnswers.any((w) => w.toUpperCase() == _currentGuess)) {
      _shake('Not in word list');
      return;
    }

    final guess = _currentGuess;
    _guesses.add(guess);
    _currentGuess = '';

    // Calculate tile states and update keyboard
    final states = _evaluateGuess(guess);
    for (int i = 0; i < _wordLength; i++) {
      final letter = guess[i];
      final state = states[i];
      // Only upgrade keyboard state (correct > present > absent)
      final current = _keyStates[letter];
      if (current == null || current == TileState.absent ||
          (current == TileState.present && state == TileState.correct)) {
        _keyStates[letter] = state;
      }
    }

    // Check win/loss
    if (guess == _answer) {
      _gameOver = true;
      _won = true;
      _streak++;
      _gamesWon++;
      _gamesPlayed++;
      if (_streak > _bestStreak) _bestStreak = _streak;
      _message = ['Genius!', 'Magnificent!', 'Impressive!', 'Splendid!', 'Great!', 'Phew!'][_guesses.length - 1];
      HapticFeedback.heavyImpact();
      _bounceCtrl?.forward(from: 0);
      _saveStats();
    } else if (_guesses.length >= _maxGuesses) {
      _gameOver = true;
      _won = false;
      _streak = 0;
      _gamesPlayed++;
      _message = _answer;
      HapticFeedback.heavyImpact();
      _saveStats();
    } else {
      HapticFeedback.mediumImpact();
    }

    setState(() {});
  }

  List<TileState> _evaluateGuess(String guess) {
    final states = List.filled(_wordLength, TileState.absent);
    final answerChars = _answer.split('');
    final used = List.filled(_wordLength, false);

    // First pass: find correct positions
    for (int i = 0; i < _wordLength; i++) {
      if (guess[i] == answerChars[i]) {
        states[i] = TileState.correct;
        used[i] = true;
      }
    }

    // Second pass: find present letters
    for (int i = 0; i < _wordLength; i++) {
      if (states[i] == TileState.correct) continue;
      for (int j = 0; j < _wordLength; j++) {
        if (!used[j] && guess[i] == answerChars[j]) {
          states[i] = TileState.present;
          used[j] = true;
          break;
        }
      }
    }

    return states;
  }

  void _shake(String msg) {
    _message = msg;
    _shakeCtrl?.forward(from: 0);
    HapticFeedback.heavyImpact();
    setState(() {});
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _message = '');
    });
  }

  @override
  Widget build(BuildContext context) {
  void _useHint() {
    if (_hintsUsed >= _maxHints || _gameOver) return;

    // Find positions that haven't been revealed yet and aren't already correctly guessed
    final unrevealed = <int>[];
    for (int i = 0; i < _wordLength; i++) {
      if (_revealedPositions.contains(i)) continue;
      // Check if this position was already correctly guessed
      bool alreadyCorrect = false;
      for (final guess in _guesses) {
        if (guess[i] == _answer[i]) {
          alreadyCorrect = true;
          break;
        }
      }
      if (!alreadyCorrect) unrevealed.add(i);
    }

    if (unrevealed.isEmpty) {
      setState(() => _message = 'No more letters to reveal!');
      return;
    }

    // Reveal a random unrevealed position
    final pos = unrevealed[Random().nextInt(unrevealed.length)];
    setState(() {
      _hintsUsed++;
      _revealedPositions.add(pos);
      _message = 'Hint: Position ${pos + 1} is "${_answer[pos]}" ($_hintsUsed/$_maxHints used)';
      // Also mark the key as present on keyboard
      _keyStates[_answer[pos]] = TileState.present;
    });
    HapticFeedback.mediumImpact();
  }

    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Wordle'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context)),
        actions: [
          // Hint button
          if (!_gameOver)
            Stack(
              children: [
                IconButton(
                  icon: Icon(Icons.lightbulb_rounded,
                    color: _hintsUsed < _maxHints ? GameTheme.accent : GameTheme.textSecondary),
                  onPressed: _hintsUsed < _maxHints ? _useHint : null),
                Positioned(right: 6, top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: GameTheme.accent,
                      shape: BoxShape.circle),
                    child: Text('${_maxHints - _hintsUsed}',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black)),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, color: GameTheme.textSecondary),
            onPressed: _showStats),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Wordle')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Message
            SizedBox(
              height: 36,
              child: Center(
                child: _message.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _gameOver && !_won ? GameTheme.accentAlt.withValues(alpha: 0.2) : GameTheme.surface,
                        borderRadius: BorderRadius.circular(8)),
                      child: Text(_message,
                        style: TextStyle(
                          fontSize: _gameOver && !_won ? 18 : 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: _gameOver && !_won ? 2 : 0,
                          color: _gameOver && _won ? GameTheme.accent
                            : _gameOver ? GameTheme.accentAlt : GameTheme.textPrimary)),
                    )
                  : null,
              ),
            ),

            // Grid
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxTileSize = min(
                        (constraints.maxWidth - 20) / _wordLength,
                        (constraints.maxHeight - 20) / _maxGuesses,
                      ).clamp(0.0, 64.0);

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_maxGuesses, (row) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(_wordLength, (col) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: _buildTile(row, col, maxTileSize),
                                );
                              }),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Game over buttons
            if (_gameOver)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GameTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _newGame,
                  child: const Text('New Game',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
              ),

            // Keyboard
            _buildKeyboard(),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(int row, int col, double size) {
    String letter = '';
    TileState state = TileState.empty;

    if (row < _guesses.length) {
      // Submitted guess
      letter = _guesses[row][col];
      final states = _evaluateGuess(_guesses[row]);
      state = states[col];
    } else if (row == _guesses.length && col < _currentGuess.length) {
      // Current input
      letter = _currentGuess[col];
      state = TileState.filled;
    }

    Color bgColor;
    Color borderColor;
    switch (state) {
      case TileState.correct:
        bgColor = const Color(0xFF538D4E);
        borderColor = const Color(0xFF538D4E);
      case TileState.present:
        bgColor = const Color(0xFFB59F3B);
        borderColor = const Color(0xFFB59F3B);
      case TileState.absent:
        bgColor = const Color(0xFF3A3A3C);
        borderColor = const Color(0xFF3A3A3C);
      case TileState.filled:
        bgColor = Colors.transparent;
        borderColor = const Color(0xFF565758);
      case TileState.empty:
        bgColor = Colors.transparent;
        borderColor = const Color(0xFF3A3A3C);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(letter,
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w800,
            color: state == TileState.filled || state == TileState.empty
              ? GameTheme.textPrimary : Colors.white,
          )),
      ),
    );
  }

  Widget _buildKeyboard() {
    const rows = [
      ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
      ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
      ['ENTER', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '⌫'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((key) {
                final isWide = key == 'ENTER' || key == '⌫';
                final state = _keyStates[key];

                Color bgColor = GameTheme.surfaceLight;
                Color textColor = GameTheme.textPrimary;
                if (state == TileState.correct) {
                  bgColor = const Color(0xFF538D4E);
                  textColor = Colors.white;
                } else if (state == TileState.present) {
                  bgColor = const Color(0xFFB59F3B);
                  textColor = Colors.white;
                } else if (state == TileState.absent) {
                  bgColor = const Color(0xFF3A3A3C);
                  textColor = const Color(0xFF818384);
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () => _onKey(key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isWide ? 52 : 32,
                      height: 48,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(6)),
                      child: Center(
                        child: Text(
                          key == '⌫' ? '⌫' : key,
                          style: TextStyle(
                            fontSize: isWide ? 11 : 15,
                            fontWeight: FontWeight.w700,
                            color: textColor),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showStats() {
    final winRate = _gamesPlayed > 0 ? (_gamesWon * 100 / _gamesPlayed).round() : 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: GameTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _statBox('$_gamesPlayed', 'Played'),
            _statBox('$winRate%', 'Win Rate'),
            _statBox('$_streak', 'Streak'),
            _statBox('$_bestStreak', 'Best'),
          ]),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _statBox(String value, String label) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
      Text(label, style: const TextStyle(fontSize: 11, color: GameTheme.textSecondary)),
    ]);
  }
}
