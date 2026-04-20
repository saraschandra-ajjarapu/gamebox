import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../../core/widgets/high_score_dialog.dart';
import '../data/quiz_questions.dart';

enum QuizMode { menu, topicSelect, playing, results }

// Category icons and colors
const _categoryMeta = {
  'Science': (Icons.science_rounded, [Color(0xFF4ECDC4), Color(0xFF2EAF9F)]),
  'Geography': (Icons.public_rounded, [Color(0xFF667EEA), Color(0xFF764BA2)]),
  'Universal Facts': (Icons.lightbulb_rounded, [Color(0xFFEDC53F), Color(0xFFE8A520)]),
  'Friends TV Series': (Icons.tv_rounded, [Color(0xFFFF6B6B), Color(0xFFEE5A24)]),
  'Cricket': (Icons.sports_cricket_rounded, [Color(0xFFA8E063), Color(0xFF56AB2F)]),
  'Countries & Capitals': (Icons.flag_rounded, [Color(0xFF1565C0), Color(0xFF0D47A1)]),
  'Telugu Movies': (Icons.movie_rounded, [Color(0xFFFF9A9E), Color(0xFFFF6B8A)]),
  'Know India': (Icons.temple_hindu_rounded, [Color(0xFFFF9800), Color(0xFFE65100)]),
  'Random': (Icons.shuffle_rounded, [Color(0xFFFF8A65), Color(0xFFFF5722)]),
};

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with TickerProviderStateMixin {
  QuizMode _mode = QuizMode.menu;
  bool _isMultiplayer = false;
  int _playerCount = 1;
  String _selectedCategory = '';

  // Game state
  List<QuizQuestion> _questions = [];
  int _currentQ = 0;
  int _selectedAnswer = -1;
  bool _answered = false;
  List<int> _scores = []; // score per player
  int _currentPlayer = 0; // for pass-and-play multiplayer
  Timer? _timer;
  int _timeLeft = 15; // seconds per question
  List<String> _playerNames = ['Player 1'];

  // Animations
  AnimationController? _correctAnimCtrl;
  AnimationController? _timerAnimCtrl;

  @override
  void initState() {
    super.initState();
    _correctAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _timerAnimCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 15));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _correctAnimCtrl?.dispose();
    _timerAnimCtrl?.dispose();
    super.dispose();
  }

  // ── Question history (persistent dedup) ─────────────────────────────

  Set<String> _askedQuestions = {};

  Future<void> _loadAskedQuestions(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'quiz_asked_$category';
    final list = prefs.getStringList(key) ?? [];
    _askedQuestions = list.toSet();
  }

  Future<void> _saveAskedQuestions(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'quiz_asked_$category';
    // Keep only last 100 to allow recycling after many games
    final list = _askedQuestions.toList();
    if (list.length > 100) list.removeRange(0, list.length - 100);
    await prefs.setStringList(key, list);
  }

  Future<List<QuizQuestion>> _getDeduplicatedQuestions(String category, {int count = 25}) async {
    await _loadAskedQuestions(category);
    final questions = getQuestions(category, count: count, askedQuestions: _askedQuestions);
    // Track what we just asked
    for (final q in questions) {
      _askedQuestions.add(q.question);
    }
    await _saveAskedQuestions(category);
    return questions;
  }

  // ── Solo / Pass-and-play ──────────────────────────────────────────────

  Future<void> _startSoloGame(String category) async {
    _selectedCategory = category;
    _questions = await _getDeduplicatedQuestions(category);
    _currentQ = 0;
    _selectedAnswer = -1;
    _answered = false;
    _scores = [0];
    _currentPlayer = 0;
    _playerNames = ['You'];
    _isMultiplayer = false;
    _mode = QuizMode.playing;
    _startTimer();
    setState(() {});
  }

  Future<void> _startLocalMultiplayer(String category, int players) async {
    _selectedCategory = category;
    _questions = await _getDeduplicatedQuestions(category);
    _currentQ = 0;
    _selectedAnswer = -1;
    _answered = false;
    _playerCount = players;
    _scores = List.filled(players, 0);
    _currentPlayer = 0;
    _isMultiplayer = true;
    _playerNames = List.generate(players, (i) => 'Player ${i + 1}');
    _mode = QuizMode.playing;
    _startTimer();
    setState(() {});
  }

  void _startTimer() {
    _timeLeft = 15;
    _timer?.cancel();
    _timerAnimCtrl?.reset();
    _timerAnimCtrl?.forward();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          t.cancel();
          _onTimeUp();
        }
      });
    });
  }

  void _onTimeUp() {
    if (_answered) return;
    _answered = true;
    HapticFeedback.heavyImpact();
    setState(() {});
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _nextQuestion();
    });
  }

  void _selectAnswer(int index) {
    if (_answered) return;
    _timer?.cancel();
    _selectedAnswer = index;
    _answered = true;

    if (index == _questions[_currentQ].correctIndex) {
      _scores[_currentPlayer] += 10 + _timeLeft; // bonus for speed
      _correctAnimCtrl?.forward(from: 0);
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    setState(() {});
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _nextQuestion();
    });
  }

  void _nextQuestion() {
    if (_isMultiplayer) {
      _currentPlayer = (_currentPlayer + 1) % _playerCount;
    }

    _currentQ++;
    final totalQuestions = _isMultiplayer ? 25 : 10;
    if (_currentQ >= _questions.length || _currentQ >= totalQuestions) {
      _mode = QuizMode.results;
      _timer?.cancel();
      setState(() {});
      if (!_isMultiplayer && _scores.isNotEmpty) {
        final finalScore = _scores[0];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          HighScoreDialog.submitIfQualifies(
            context: context, gameId: 'quiz', gameName: 'Quiz',
            score: finalScore);
        });
      }
      return;
    }

    _selectedAnswer = -1;
    _answered = false;
    _startTimer();
    setState(() {});
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case QuizMode.menu:
        return _buildMenu();
      case QuizMode.topicSelect:
        return _buildTopicSelect();
      case QuizMode.playing:
        return _buildGame();
      case QuizMode.results:
        return _buildResults();
    }
  }

  Widget _buildMenu() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Quiz'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: GameTheme.accent),
            onPressed: () => GameHelp.show(context, 'Quiz')),
        ],
      ),
      body: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.quiz_rounded, size: 64, color: GameTheme.accent),
          const SizedBox(height: 12),
          const Text('Quiz', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Test your knowledge!', style: TextStyle(fontSize: 14, color: GameTheme.textSecondary)),
          const SizedBox(height: 40),

          _menuBtn(Icons.person_rounded, 'Solo', 'Play with timer', () {
            _isMultiplayer = false;
            _playerCount = 1;
            setState(() => _mode = QuizMode.topicSelect);
          }),
          const SizedBox(height: 12),

          _menuBtn(Icons.people_rounded, 'Pass & Play', '2-4 players, same device', () {
            _showPlayerCountPicker();
          }),
        ]))),
    );
  }

  void _showPlayerCountPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: GameTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('How many players?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (int i = 2; i <= 4; i++)
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _playerCount = i;
                  _isMultiplayer = true;
                  setState(() => _mode = QuizMode.topicSelect);
                },
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    color: GameTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: GameTheme.border)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$i', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: GameTheme.accent)),
                    Text('players', style: const TextStyle(fontSize: 10, color: GameTheme.textSecondary)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _buildTopicSelect() {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Choose Topic'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: GameTheme.textPrimary),
          onPressed: () => setState(() => _mode = QuizMode.menu))),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: 1.3,
        children: quizCategories.map((cat) {
          final meta = _categoryMeta[cat]!;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (_isMultiplayer) {
                _startLocalMultiplayer(cat, _playerCount);
              } else {
                _startSoloGame(cat);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: meta.$2, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: meta.$2.first.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(meta.$1, size: 36, color: Colors.white),
                const SizedBox(height: 8),
                Text(cat, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGame() {
    final q = _questions[_currentQ];
    final totalQ = _isMultiplayer ? min(_questions.length, 25) : min(_questions.length, 10);
    final progress = (_currentQ + 1) / totalQ;

    return Scaffold(
      backgroundColor: GameTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // Top bar — scores + timer
              Row(children: [
                // Back
                GestureDetector(
                  onTap: () {
                    _timer?.cancel();
                    setState(() => _mode = QuizMode.menu);
                  },
                  child: const Icon(Icons.close_rounded, color: GameTheme.textSecondary)),
                const SizedBox(width: 12),

                // Progress
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: GameTheme.surface,
                      color: GameTheme.accent,
                      minHeight: 6),
                  ),
                ),
                const SizedBox(width: 12),

                // Timer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _timeLeft <= 5 ? GameTheme.accentAlt.withValues(alpha: 0.2) : GameTheme.surface,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('${_timeLeft}s',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: _timeLeft <= 5 ? GameTheme.accentAlt : GameTheme.textPrimary)),
                ),
              ]),

              const SizedBox(height: 8),

              // Current player indicator (multiplayer)
              if (_isMultiplayer)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: GameTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('${_playerNames[_currentPlayer]}\'s turn',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GameTheme.accent)),
                ),

              const SizedBox(height: 8),

              // Question number + category
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: GameTheme.surface,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('Q${_currentQ + 1}/$totalQ',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GameTheme.textSecondary)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: GameTheme.surface,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(q.category,
                    style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary)),
                ),
              ]),

              const SizedBox(height: 20),

              // Question
              Expanded(
                child: SingleChildScrollView(
                  child: Column(children: [
                    Text(q.question,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GameTheme.textPrimary, height: 1.4)),
                    const SizedBox(height: 28),

                    // Options
                    for (int i = 0; i < q.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _optionCard(i, q),
                      ),
                  ]),
                ),
              ),

              // Score bar
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (int i = 0; i < _scores.length; i++)
                      Text('${_playerNames[i]}: ${_scores[i]}',
                        style: TextStyle(fontSize: 13,
                          fontWeight: i == _currentPlayer ? FontWeight.w700 : FontWeight.normal,
                          color: i == _currentPlayer ? GameTheme.accent : GameTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionCard(int index, QuizQuestion q) {
    final isCorrect = index == q.correctIndex;
    final isSelected = _selectedAnswer == index;
    Color bgColor = GameTheme.surface;
    Color borderColor = GameTheme.border;
    Color textColor = GameTheme.textPrimary;

    if (_answered) {
      if (isCorrect) {
        bgColor = const Color(0xFF1B5E20).withValues(alpha: 0.3);
        borderColor = const Color(0xFF4CAF50);
        textColor = const Color(0xFF81C784);
      } else if (isSelected && !isCorrect) {
        bgColor = const Color(0xFFB71C1C).withValues(alpha: 0.3);
        borderColor = const Color(0xFFEF5350);
        textColor = const Color(0xFFEF9A9A);
      }
    }

    final labels = ['A', 'B', 'C', 'D'];

    return GestureDetector(
      onTap: () => _selectAnswer(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1)),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: isSelected ? borderColor.withValues(alpha: 0.2) : GameTheme.surfaceLight,
              borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(labels[index],
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(q.options[index],
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textColor)),
          ),
          if (_answered && isCorrect)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 22),
          if (_answered && isSelected && !isCorrect)
            const Icon(Icons.cancel_rounded, color: Color(0xFFEF5350), size: 22),
        ]),
      ),
    );
  }

  Widget _buildResults() {
    final winner = _scores.indexOf(_scores.reduce(max));
    final isSolo = _scores.length == 1;

    return Scaffold(
      backgroundColor: GameTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.emoji_events_rounded, size: 64, color: GameTheme.gold),
              const SizedBox(height: 16),
              Text(isSolo ? 'Quiz Complete!' : '${_playerNames[winner]} Wins!',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: GameTheme.textPrimary)),
              const SizedBox(height: 8),
              Text(_selectedCategory,
                style: const TextStyle(fontSize: 14, color: GameTheme.textSecondary)),
              const SizedBox(height: 32),

              // Scores
              for (int i = 0; i < _scores.length; i++)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: i == winner ? GameTheme.accent.withValues(alpha: 0.15) : GameTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: i == winner ? GameTheme.accent : GameTheme.border)),
                  child: Row(children: [
                    if (i == winner)
                      const Icon(Icons.star_rounded, color: GameTheme.gold, size: 22)
                    else
                      Text('${i + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GameTheme.textSecondary)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_playerNames[i],
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                        color: i == winner ? GameTheme.accent : GameTheme.textPrimary))),
                    Text('${_scores[i]} pts',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: i == winner ? GameTheme.accent : GameTheme.textPrimary)),
                  ]),
                ),

              const SizedBox(height: 32),

              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: GameTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => setState(() => _mode = QuizMode.topicSelect),
                  child: const Text('Play Again', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: GameTheme.accent),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => setState(() => _mode = QuizMode.menu),
                  child: const Text('Menu', style: TextStyle(fontWeight: FontWeight.w700, color: GameTheme.accent))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(IconData icon, String label, String sub, VoidCallback onTap) {
    return GestureDetector(onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(color: GameTheme.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GameTheme.border)),
        child: Row(children: [Icon(icon, color: GameTheme.accent, size: 26), const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GameTheme.textPrimary)),
            Text(sub, style: const TextStyle(fontSize: 12, color: GameTheme.textSecondary))])),
          const Icon(Icons.arrow_forward_ios_rounded, color: GameTheme.textSecondary, size: 16)])));
  }
}
