import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/widgets/high_score_dialog.dart';

enum MemoryMode { menu, playing }
enum Difficulty { easy, medium, hard }

class MemoryCard {
  final int id;
  final String emoji;
  bool isFaceUp;
  bool isMatched;

  MemoryCard({required this.id, required this.emoji})
      : isFaceUp = false, isMatched = false;
}

// Emoji sets by category
const _animalEmojis = ['🐶', '🐱', '🐼', '🦁', '🐸', '🐵', '🐷', '🐰',
    '🦊', '🐻', '🐨', '🐯', '🦋', '🐙', '🦄', '🐬', '🦜', '🐢'];
const _foodEmojis = ['🍎', '🍕', '🍩', '🍉', '🍓', '🌮', '🍦', '🧁',
    '🍔', '🍟', '🥑', '🍇', '🍌', '🥕', '🍪', '🧀', '🍰', '🥐'];
const _sportEmojis = ['⚽', '🏀', '🎾', '🏈', '⚾', '🎯', '🏓', '🎳',
    '🥊', '🏸', '⛳', '🏊', '🚴', '⛷️', '🏄', '🤸', '🎮', '🏆'];

class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({super.key});

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen>
    with TickerProviderStateMixin {
  MemoryMode _mode = MemoryMode.menu;
  Difficulty _difficulty = Difficulty.medium;
  List<MemoryCard> _cards = [];
  int _firstIndex = -1;
  int _secondIndex = -1;
  bool _waiting = false;
  int _moves = 0;
  int _matchesFound = 0;
  int _totalPairs = 0;
  bool _gameOver = false;
  int _bestMoves = 0;
  int _emojiSet = 0; // 0=animals, 1=food, 2=sports
  final _random = Random();

  // Timer
  Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _timeDisplay = '0:00';

  // Flip animations
  final Map<int, AnimationController> _flipAnims = {};

  List<String> get _currentEmojis => switch (_emojiSet) {
    0 => _animalEmojis,
    1 => _foodEmojis,
    2 => _sportEmojis,
    _ => _animalEmojis,
  };

  int get _gridCols => switch (_difficulty) {
    Difficulty.easy => 3,
    Difficulty.medium => 4,
    Difficulty.hard => 4,
  };

  int get _gridRows => switch (_difficulty) {
    Difficulty.easy => 4,
    Difficulty.medium => 4,
    Difficulty.hard => 5,
  };

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _flipAnims.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _startGame() {
    final pairs = (_gridCols * _gridRows) ~/ 2;
    _totalPairs = pairs;
    _matchesFound = 0;
    _moves = 0;
    _gameOver = false;
    _firstIndex = -1;
    _secondIndex = -1;
    _waiting = false;

    // Pick random emojis
    final emojis = List<String>.from(_currentEmojis)..shuffle(_random);
    final selected = emojis.take(pairs).toList();

    // Create pairs and shuffle
    _cards = [];
    for (int i = 0; i < pairs; i++) {
      _cards.add(MemoryCard(id: i, emoji: selected[i]));
      _cards.add(MemoryCard(id: i, emoji: selected[i]));
    }
    _cards.shuffle(_random);

    // Reset animations
    for (final c in _flipAnims.values) {
      c.dispose();
    }
    _flipAnims.clear();

    // Timer
    _stopwatch = Stopwatch()..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_gameOver) {
        setState(() {
          final secs = _stopwatch.elapsed.inSeconds;
          _timeDisplay = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
        });
      }
    });

    _mode = MemoryMode.playing;
    setState(() {});
  }

  void _onCardTap(int index) {
    if (_waiting || _gameOver) return;
    if (_cards[index].isFaceUp || _cards[index].isMatched) return;

    // Flip card face up
    _cards[index].isFaceUp = true;
    _animateFlip(index);
    HapticFeedback.lightImpact();

    if (_firstIndex == -1) {
      _firstIndex = index;
      setState(() {});
      return;
    }

    // Second card flipped
    _secondIndex = index;
    _moves++;
    setState(() {});

    // Check match
    if (_cards[_firstIndex].id == _cards[_secondIndex].id) {
      // Match!
      _cards[_firstIndex].isMatched = true;
      _cards[_secondIndex].isMatched = true;
      _matchesFound++;
      HapticFeedback.heavyImpact();

      _firstIndex = -1;
      _secondIndex = -1;

      if (_matchesFound == _totalPairs) {
        _gameOver = true;
        _stopwatch.stop();
        _timer?.cancel();
        if (_bestMoves == 0 || _moves < _bestMoves) {
          _bestMoves = _moves;
        }
        final finalMoves = _moves;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          HighScoreDialog.submitIfQualifies(
            context: context, gameId: 'memory', gameName: 'Memory',
            score: finalMoves, scoreLabel: 'Moves');
        });
      }
      setState(() {});
    } else {
      // No match — flip back after delay
      _waiting = true;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _cards[_firstIndex].isFaceUp = false;
        _cards[_secondIndex].isFaceUp = false;
        _firstIndex = -1;
        _secondIndex = -1;
        _waiting = false;
        setState(() {});
      });
    }
  }

  void _animateFlip(int index) {
    _flipAnims[index]?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _flipAnims[index] = ctrl;
    ctrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == MemoryMode.menu) return _buildMenu();
    return _buildGame();
  }

  // ── Menu ────────────────────────────────────────────────────────────────

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Memory Match'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Memory'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧠', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 8),
              const Text('Memory Match',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                      color: GameTheme.textPrimary)),
              const SizedBox(height: 32),

              // Difficulty
              const Text('DIFFICULTY', style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: GameTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _difficultyChip('Easy', '3×4', Difficulty.easy),
                  const SizedBox(width: 8),
                  _difficultyChip('Medium', '4×4', Difficulty.medium),
                  const SizedBox(width: 8),
                  _difficultyChip('Hard', '4×5', Difficulty.hard),
                ],
              ),

              const SizedBox(height: 24),

              // Emoji theme
              const Text('THEME', style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: GameTheme.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _emojiThemeChip('Animals', '🐶', 0),
                  const SizedBox(width: 8),
                  _emojiThemeChip('Food', '🍕', 1),
                  const SizedBox(width: 8),
                  _emojiThemeChip('Sports', '⚽', 2),
                ],
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GameTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Start Game',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _difficultyChip(String label, String size, Difficulty diff) {
    final selected = _difficulty == diff;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _difficulty = diff);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
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
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: selected ? GameTheme.accent : GameTheme.textPrimary)),
              Text(size, style: TextStyle(fontSize: 11,
                  color: selected ? GameTheme.accent : GameTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emojiThemeChip(String label, String emoji, int index) {
    final selected = _emojiSet == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _emojiSet = index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: selected ? GameTheme.accent : GameTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Game ─────────────────────────────────────────────────────────────────

  Widget _buildGame() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Memory Match'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () {
            _timer?.cancel();
            _stopwatch.stop();
            setState(() => _mode = MemoryMode.menu);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: GameTheme.accent),
            onPressed: _startGame,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availW = constraints.maxWidth - 32;
            final availH = constraints.maxHeight - 140;
            final cellW = availW / _gridCols;
            final cellH = availH / _gridRows;
            final cardSize = min(cellW, cellH) - 8;

            return Column(
              children: [
                // Stats bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statChip('⏱️', _timeDisplay),
                      _statChip('👆', '$_moves moves'),
                      _statChip('✅', '$_matchesFound/$_totalPairs'),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Card grid
                Expanded(
                  child: Center(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: List.generate(_cards.length, (i) =>
                          _buildCard(i, cardSize)),
                    ),
                  ),
                ),

                // Game over
                if (_gameOver)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
                        const Text('🎉', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 8),
                        Text('Complete in $_moves moves!',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                                color: GameTheme.accent)),
                        Text('Time: $_timeDisplay',
                            style: const TextStyle(fontSize: 14, color: GameTheme.textSecondary)),
                        if (_bestMoves > 0)
                          Text('Best: $_bestMoves moves',
                              style: const TextStyle(fontSize: 12, color: GameTheme.gold)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _startGame,
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
                              onPressed: () {
                                _timer?.cancel();
                                setState(() => _mode = MemoryMode.menu);
                              },
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
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statChip(String icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: GameTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameTheme.border),
      ),
      child: Text('$icon $value',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: GameTheme.textPrimary)),
    );
  }

  Widget _buildCard(int index, double size) {
    final card = _cards[index];
    final showFace = card.isFaceUp || card.isMatched;

    return GestureDetector(
      onTap: () => _onCardTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: card.isMatched
              ? GameTheme.accent.withValues(alpha: 0.15)
              : showFace
                  ? const Color(0xFF1E3040)
                  : GameTheme.accent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: card.isMatched
                ? GameTheme.accent.withValues(alpha: 0.4)
                : showFace
                    ? GameTheme.border
                    : GameTheme.accent,
            width: 2,
          ),
          boxShadow: !card.isMatched
              ? [BoxShadow(
                  color: (showFace ? GameTheme.border : GameTheme.accent).withValues(alpha: 0.3),
                  blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Center(
          child: showFace
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.5, end: 1.0),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Text(card.emoji, style: TextStyle(fontSize: size * 0.45)),
                )
              : Icon(Icons.question_mark_rounded,
                  color: Colors.white.withValues(alpha: 0.6), size: size * 0.35),
        ),
      ),
    );
  }
}
