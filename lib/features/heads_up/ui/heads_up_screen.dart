import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../data/word_lists.dart';

enum _Phase { setup, getReady, playing, roundOver, gameOver }

class _Team {
  String name;
  Color color;
  int score;
  _Team(this.name, this.color) : score = 0;
}

class HeadsUpScreen extends StatefulWidget {
  const HeadsUpScreen({super.key});

  @override
  State<HeadsUpScreen> createState() => _HeadsUpScreenState();
}

class _HeadsUpScreenState extends State<HeadsUpScreen> {
  static const List<Color> _teamPalette = [
    Color(0xFF4ECDC4), // teal
    Color(0xFFEF5350), // red
    Color(0xFFFFD93D), // gold
    Color(0xFF7B68EE), // purple
    Color(0xFF66BB6A), // green
    Color(0xFFFF9800), // orange
  ];

  _Phase _phase = _Phase.setup;

  // Setup state
  final List<TextEditingController> _teamControllers = [
    TextEditingController(text: 'Team 1'),
    TextEditingController(text: 'Team 2'),
  ];
  final List<int> _teamColorIndexes = [0, 1];
  HeadsUpCategory _category = HeadsUpCategory.mix;
  int _targetPoints = 15;
  int _timerSeconds = 90; // 1:30

  // Game state
  final List<_Team> _teams = [];
  int _currentTeamIndex = 0;
  List<String> _wordDeck = [];
  int _deckIndex = 0;
  String _currentWord = '';
  Timer? _timer;
  int _timeLeft = 0;
  int _roundCorrect = 0;
  int _roundSkipped = 0;
  int _feedbackTicks = 0; // shows a flash briefly after correct/skip
  bool _lastWasCorrect = true;
  int _winnerIndex = -1;

  final _rng = Random();

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _teamControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Setup helpers ─────────────────────────────────────────────────────────

  void _addTeam() {
    if (_teamControllers.length >= 4) return;
    final nextIdx = _teamControllers.length;
    _teamControllers.add(TextEditingController(text: 'Team ${nextIdx + 1}'));
    // Pick a color not already taken if possible
    final unused = List.generate(_teamPalette.length, (i) => i)
      ..removeWhere(_teamColorIndexes.contains);
    _teamColorIndexes.add(unused.isNotEmpty ? unused.first : nextIdx);
    setState(() {});
  }

  void _removeTeam(int i) {
    if (_teamControllers.length <= 2) return;
    _teamControllers.removeAt(i).dispose();
    _teamColorIndexes.removeAt(i);
    setState(() {});
  }

  void _pickColor(int teamIdx) async {
    HapticFeedback.selectionClick();
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: GameTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Pick team color',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GameTheme.textPrimary)),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (int i = 0; i < _teamPalette.length; i++)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, i),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _teamPalette[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: i == _teamColorIndexes[teamIdx]
                              ? Colors.white
                              : Colors.transparent,
                          width: 3),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _teamColorIndexes[teamIdx] = picked);
    }
  }

  // ── Game flow ─────────────────────────────────────────────────────────────

  void _startMatch() {
    _teams.clear();
    for (int i = 0; i < _teamControllers.length; i++) {
      final name = _teamControllers[i].text.trim();
      _teams.add(_Team(
        name.isEmpty ? 'Team ${i + 1}' : name,
        _teamPalette[_teamColorIndexes[i]],
      ));
    }
    _wordDeck = [..._category.words()]..shuffle(_rng);
    _deckIndex = 0;
    _currentTeamIndex = 0;
    _winnerIndex = -1;
    _phase = _Phase.getReady;
    setState(() {});
  }

  void _startRound() {
    _roundCorrect = 0;
    _roundSkipped = 0;
    _timeLeft = _timerSeconds;
    _nextWord();
    _phase = _Phase.playing;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    setState(() {});
  }

  void _tick() {
    if (!mounted || _phase != _Phase.playing) return;
    setState(() {
      _timeLeft--;
      if (_feedbackTicks > 0) _feedbackTicks--;
      if (_timeLeft <= 0) {
        _timer?.cancel();
        _endRound();
      }
    });
  }

  void _nextWord() {
    if (_wordDeck.isEmpty) {
      _currentWord = '—';
      return;
    }
    if (_deckIndex >= _wordDeck.length) {
      // Reshuffle if we run out mid-match (unlikely with 300+ words in Mix)
      _wordDeck.shuffle(_rng);
      _deckIndex = 0;
    }
    _currentWord = _wordDeck[_deckIndex++];
  }

  void _markCorrect() {
    if (_phase != _Phase.playing) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _roundCorrect++;
      _lastWasCorrect = true;
      _feedbackTicks = 1;
      _nextWord();
    });
  }

  void _markSkip() {
    if (_phase != _Phase.playing) return;
    HapticFeedback.lightImpact();
    setState(() {
      _roundSkipped++;
      _lastWasCorrect = false;
      _feedbackTicks = 1;
      _nextWord();
    });
  }

  void _endRound() {
    _timer?.cancel();
    final team = _teams[_currentTeamIndex];
    team.score += _roundCorrect;
    _phase = _Phase.roundOver;
    HapticFeedback.heavyImpact();

    // Check for winner
    final leader = _teams.reduce((a, b) => a.score >= b.score ? a : b);
    if (leader.score >= _targetPoints) {
      _winnerIndex = _teams.indexOf(leader);
      _phase = _Phase.gameOver;
    }
    setState(() {});
  }

  void _nextTeam() {
    _currentTeamIndex = (_currentTeamIndex + 1) % _teams.length;
    _phase = _Phase.getReady;
    setState(() {});
  }

  void _resetMatch() {
    _timer?.cancel();
    _phase = _Phase.setup;
    setState(() {});
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Headsup! / Dumb Charades'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: GameTheme.textPrimary),
          onPressed: () {
            _timer?.cancel();
            Navigator.pop(context);
          },
        ),
        actions: [
          if (_phase == _Phase.setup)
            IconButton(
              icon: const Icon(Icons.help_outline_rounded,
                  color: GameTheme.accent),
              onPressed: () => GameHelp.show(context, 'Headsup!'),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.setup => _buildSetup(),
          _Phase.getReady => _buildGetReady(),
          _Phase.playing => _buildPlaying(),
          _Phase.roundOver => _buildRoundOver(),
          _Phase.gameOver => _buildGameOver(),
        },
      ),
    );
  }

  // ── Setup ─────────────────────────────────────────────────────────────────

  Widget _buildSetup() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Teams'),
          const SizedBox(height: 8),
          for (int i = 0; i < _teamControllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                GestureDetector(
                  onTap: () => _pickColor(i),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _teamPalette[_teamColorIndexes[i]],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _teamControllers[i],
                    maxLength: 16,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                        color: GameTheme.textPrimary,
                        fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: GameTheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                if (_teamControllers.length > 2)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: GameTheme.accentAlt),
                    onPressed: () => _removeTeam(i),
                  ),
              ]),
            ),
          if (_teamControllers.length < 4)
            TextButton.icon(
              onPressed: _addTeam,
              icon: const Icon(Icons.add_circle_outline,
                  color: GameTheme.accent),
              label: const Text('Add team',
                  style: TextStyle(
                      color: GameTheme.accent,
                      fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 20),
          _sectionTitle('Category'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in HeadsUpCategory.values) _categoryChip(c),
          ]),
          const SizedBox(height: 24),
          _sectionTitle('Points to win'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in [10, 15, 20, 25]) _pointsChip(p),
          ]),
          const SizedBox(height: 24),
          _sectionTitle('Time per round'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in [30, 60, 90, 120, 180])
              _timerChip(s),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startMatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: GameTheme.accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Start match',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) => Text(label,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: GameTheme.textSecondary));

  Widget _categoryChip(HeadsUpCategory c) {
    final selected = c == _category;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _category = c);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? GameTheme.accent : GameTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GameTheme.accent, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(c.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(c.label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : GameTheme.textPrimary)),
        ]),
      ),
    );
  }

  Widget _pointsChip(int p) => _smallChip(
        label: '$p pts',
        selected: _targetPoints == p,
        onTap: () => setState(() => _targetPoints = p),
      );

  Widget _timerChip(int s) {
    final label = s < 60
        ? '${s}s'
        : s == 60
            ? '1 min'
            : '${(s / 60).toStringAsFixed(s % 60 == 0 ? 0 : 1)} min';
    return _smallChip(
      label: label,
      selected: _timerSeconds == s,
      onTap: () => setState(() => _timerSeconds = s),
    );
  }

  Widget _smallChip(
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? GameTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GameTheme.accent, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : GameTheme.accent)),
      ),
    );
  }

  // ── Get Ready ─────────────────────────────────────────────────────────────

  Widget _buildGetReady() {
    final team = _teams[_currentTeamIndex];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: team.color, shape: BoxShape.circle),
              child: const Icon(Icons.groups_rounded,
                  color: Colors.white, size: 48),
            ),
            const SizedBox(height: 16),
            Text(team.name,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: GameTheme.textPrimary)),
            const SizedBox(height: 6),
            Text('${team.score} / $_targetPoints',
                style: const TextStyle(
                    fontSize: 15, color: GameTheme.textSecondary)),
            const SizedBox(height: 28),
            const Text(
              'Hold the phone to your forehead.\nYour teammates will act or describe the word.\nTap CORRECT if you guess, SKIP to pass.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: GameTheme.textPrimary,
                  height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 220,
              child: ElevatedButton(
                onPressed: _startRound,
                style: ElevatedButton.styleFrom(
                  backgroundColor: team.color,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Start round',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Playing ───────────────────────────────────────────────────────────────

  Widget _buildPlaying() {
    final team = _teams[_currentTeamIndex];
    final flashColor = _feedbackTicks > 0
        ? (_lastWasCorrect
            ? const Color(0xFF43A047)
            : const Color(0xFFE53935))
        : null;
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 200) {
          _markCorrect();
        } else if (v < -200) {
          _markSkip();
        }
      },
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 200) {
          _markCorrect();
        } else if (v < -200) {
          _markSkip();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: flashColor ?? GameTheme.background,
        child: Column(children: [
          // Top bar: timer + team badge
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: team.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(team.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: GameTheme.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _timeLeft <= 10
                      ? GameTheme.accentAlt
                      : GameTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_formatTime(_timeLeft),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Text('✓ $_roundCorrect   ✗ $_roundSkipped',
                  style: const TextStyle(
                      fontSize: 13, color: GameTheme.textSecondary)),
            ]),
          ),
          // Word area — fills most of the screen. FittedBox scales a single
          // line so long words (Brochevarevarura) stay one line and multi-word
          // titles (Dilwale Dulhania Le Jayenge) wrap at spaces, then shrink.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _currentWord,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 140,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Big correct / skip buttons — also activated by swipes
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Row(children: [
              Expanded(
                child: _playButton(
                  label: 'SKIP',
                  icon: Icons.close_rounded,
                  color: const Color(0xFFE53935),
                  onTap: _markSkip,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _playButton(
                  label: 'CORRECT',
                  icon: Icons.check_rounded,
                  color: const Color(0xFF43A047),
                  onTap: _markCorrect,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _playButton(
      {required String label,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }

  String _formatTime(int s) {
    if (s < 0) s = 0;
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  // ── Round Over ────────────────────────────────────────────────────────────

  Widget _buildRoundOver() {
    final team = _teams[_currentTeamIndex];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: team.color, shape: BoxShape.circle),
              child: const Icon(Icons.flag_rounded,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 14),
            Text('${team.name} • $_roundCorrect correct',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: GameTheme.textPrimary)),
            const SizedBox(height: 4),
            Text('Skipped: $_roundSkipped',
                style: const TextStyle(color: GameTheme.textSecondary)),
            const SizedBox(height: 20),
            _scoreboard(),
            const SizedBox(height: 28),
            SizedBox(
              width: 240,
              child: ElevatedButton(
                onPressed: _nextTeam,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GameTheme.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Pass to next team',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Game Over ─────────────────────────────────────────────────────────────

  Widget _buildGameOver() {
    final winner = _teams[_winnerIndex];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded,
                color: GameTheme.gold, size: 72),
            const SizedBox(height: 12),
            Text('${winner.name} wins!',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: winner.color)),
            const SizedBox(height: 16),
            _scoreboard(),
            const SizedBox(height: 28),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton(
                onPressed: _resetMatch,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: GameTheme.accent),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('New match',
                    style: TextStyle(
                        color: GameTheme.accent,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _scoreboard() {
    final sorted = [..._teams]..sort((a, b) => b.score.compareTo(a.score));
    return Column(
      children: [
        for (final t in sorted)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: GameTheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: t.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: GameTheme.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${t.score}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: GameTheme.textPrimary)),
            ]),
          ),
      ],
    );
  }
}
