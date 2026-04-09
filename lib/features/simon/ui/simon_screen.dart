import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';

class SimonScreen extends StatefulWidget {
  const SimonScreen({super.key});
  @override
  State<SimonScreen> createState() => _SimonScreenState();
}

class _SimonScreenState extends State<SimonScreen> {
  static const _colors = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFDD835)];
  static const _litColors = [Color(0xFFFF5252), Color(0xFF448AFF), Color(0xFF69F0AE), Color(0xFFFFFF00)];

  List<int> _sequence = [];
  int _playerIndex = 0;
  int _round = 0;
  int _bestScore = 0;
  bool _playing = false;
  bool _showingSequence = false;
  bool _gameOver = false;
  int _litButton = -1;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _loadBestScore();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _bestScore = prefs.getInt('best_score_simon') ?? 0);
  }

  Future<void> _saveBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score_simon', _bestScore);
  }

  void _startGame() {
    _sequence = []; _round = 0; _gameOver = false;
    _playing = true; _playerIndex = 0;
    setState(() {});
    _nextRound();
  }

  void _nextRound() {
    _round++;
    _sequence.add(_rng.nextInt(4));
    _playerIndex = 0;
    _showSequence();
  }

  Future<void> _showSequence() async {
    _showingSequence = true; setState(() {});
    await Future.delayed(const Duration(milliseconds: 400));

    final delay = max(250, 600 - _round * 20);
    for (final idx in _sequence) {
      if (!mounted) return;
      _litButton = idx; setState(() {});
      HapticFeedback.selectionClick();
      await Future.delayed(Duration(milliseconds: delay));
      _litButton = -1; setState(() {});
      await Future.delayed(Duration(milliseconds: delay ~/ 2));
    }
    _showingSequence = false; setState(() {});
  }

  void _onButtonTap(int index) {
    if (!_playing || _showingSequence || _gameOver) return;

    _litButton = index; setState(() {});
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) { _litButton = -1; setState(() {}); }
    });

    if (_sequence[_playerIndex] == index) {
      _playerIndex++;
      if (_playerIndex >= _sequence.length) {
        // Round complete
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _nextRound();
        });
      }
    } else {
      // Wrong!
      _gameOver = true; _playing = false;
      if (_round - 1 > _bestScore) { _bestScore = _round - 1; _saveBestScore(); }
      HapticFeedback.heavyImpact();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(title: const Text('Simon Says'), leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
        onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Simon Says'),
          ),
        ]),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final padSize = min(constraints.maxWidth - 48, constraints.maxHeight * 0.5);

        return Column(children: [
          const SizedBox(height: 16),
          // Score
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _statBox('Round', _playing || _gameOver ? '${_round > 0 ? (_gameOver ? _round - 1 : _round) : 0}' : '-'),
            const SizedBox(width: 16),
            _statBox('Best', '$_bestScore'),
          ]),

          const SizedBox(height: 16),

          // Status
          Text(_gameOver ? 'Wrong! Score: ${_round - 1}'
            : _showingSequence ? 'Watch...'
            : _playing ? 'Your turn' : 'Press Start',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
              color: _gameOver ? GameTheme.accentAlt : GameTheme.accent)),

          const Spacer(),

          // Simon pad
          Center(child: SizedBox(width: padSize, height: padSize,
            child: ClipRRect(borderRadius: BorderRadius.circular(padSize / 2),
              child: GridView.count(crossAxisCount: 2, physics: const NeverScrollableScrollPhysics(),
                children: List.generate(4, (i) => _simonButton(i, padSize / 2)))))),

          const Spacer(),

          // Start/Play Again
          Padding(padding: const EdgeInsets.only(bottom: 32),
            child: ElevatedButton(
              onPressed: (_playing && !_gameOver) ? null : _startGame,
              style: ElevatedButton.styleFrom(backgroundColor: GameTheme.accent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(_gameOver ? 'Play Again' : _playing ? 'Playing...' : 'Start Game',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)))),
        ]);
      })),
    );
  }

  Widget _statBox(String label, String value) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: GameTheme.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameTheme.border)),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 11, color: GameTheme.textSecondary, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: GameTheme.textPrimary))]));
  }

  Widget _simonButton(int index, double size) {
    final isLit = _litButton == index;
    final color = isLit ? _litColors[index] : _colors[index];
    // Rounded corners: TL, TR, BL, BR
    final radius = switch (index) {
      0 => const BorderRadius.only(topLeft: Radius.circular(999)),
      1 => const BorderRadius.only(topRight: Radius.circular(999)),
      2 => const BorderRadius.only(bottomLeft: Radius.circular(999)),
      3 => const BorderRadius.only(bottomRight: Radius.circular(999)),
      _ => BorderRadius.zero,
    };

    return GestureDetector(
      onTap: () => _onButtonTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: color, borderRadius: radius,
          boxShadow: isLit ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 20, spreadRadius: 2)] : null)));
  }
}
