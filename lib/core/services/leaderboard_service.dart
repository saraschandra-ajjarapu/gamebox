import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-game local leaderboard (top 10 per game).
/// Also tracks the last player name so we can pre-fill the dialog.
class LeaderboardService {
  static const _prefsKey = 'leaderboard_v1';
  static const _nameKey = 'leaderboard_last_name';
  static const maxEntries = 10;

  /// Lower-is-better games: the list is sorted ascending (fewer = better).
  /// Everything else is descending (higher = better).
  static const _lowerIsBetter = {'wordle_guesses', 'memory', 'sudoku'};

  static bool _lower(String gameId) => _lowerIsBetter.contains(gameId);

  /// Return top entries for a game, already sorted.
  static Future<List<LeaderboardEntry>> getTop(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_prefsKey}_$gameId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _sort(list, gameId);
      return list;
    } catch (_) {
      return [];
    }
  }

  /// True if a new score would make the top 10.
  static Future<bool> qualifies(String gameId, int score) async {
    if (score <= 0) return false;
    final top = await getTop(gameId);
    if (top.length < maxEntries) return true;
    final worst = top.last.score;
    return _lower(gameId) ? score < worst : score > worst;
  }

  /// Insert a new score; returns the 0-based rank (0 = #1), or -1 if it didn't qualify.
  static Future<int> submit(String gameId, String name, int score) async {
    final prefs = await SharedPreferences.getInstance();
    final top = await getTop(gameId);
    final entry = LeaderboardEntry(
      name: name.trim().isEmpty ? 'Anonymous' : name.trim(),
      score: score,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    top.add(entry);
    _sort(top, gameId);
    final trimmed = top.take(maxEntries).toList();
    final rank = trimmed.indexOf(entry);
    await prefs.setString(
      '${_prefsKey}_$gameId',
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(_nameKey, entry.name);
    return rank;
  }

  static Future<String> getLastName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey) ?? '';
  }

  static Future<void> saveLastName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name.trim());
  }

  static Future<void> clear(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_prefsKey}_$gameId');
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final g in allGames) {
      await prefs.remove('${_prefsKey}_${g.id}');
    }
  }

  static void _sort(List<LeaderboardEntry> list, String gameId) {
    if (_lower(gameId)) {
      list.sort((a, b) => a.score.compareTo(b.score));
    } else {
      list.sort((a, b) => b.score.compareTo(a.score));
    }
  }

  /// All games that participate in the leaderboard, for the leaderboard screen.
  static const allGames = <LeaderboardGame>[
    LeaderboardGame(id: '2048', name: '2048', scoreLabel: 'Score'),
    LeaderboardGame(id: 'snake_easy', name: 'Snake (Easy)', scoreLabel: 'Score'),
    LeaderboardGame(id: 'snake_normal', name: 'Snake (Normal)', scoreLabel: 'Score'),
    LeaderboardGame(id: 'snake_hard', name: 'Snake (Hard)', scoreLabel: 'Score'),
    LeaderboardGame(id: 'tetris', name: 'Tetris', scoreLabel: 'Score'),
    LeaderboardGame(id: 'pacman', name: 'Pac-Man', scoreLabel: 'Score'),
    LeaderboardGame(id: 'stack', name: 'Stack', scoreLabel: 'Height'),
    LeaderboardGame(id: 'simon', name: 'Simon Says', scoreLabel: 'Level'),
    LeaderboardGame(id: 'quiz', name: 'Quiz', scoreLabel: 'Score'),
    LeaderboardGame(id: 'wordle', name: 'Wordle Streak', scoreLabel: 'Streak'),
    LeaderboardGame(id: 'memory', name: 'Memory (fewest moves)', scoreLabel: 'Moves'),
  ];
}

class LeaderboardEntry {
  final String name;
  final int score;
  final int timestamp;

  const LeaderboardEntry({
    required this.name,
    required this.score,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {'n': name, 's': score, 't': timestamp};

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        name: (j['n'] as String?) ?? 'Anonymous',
        score: (j['s'] as num?)?.toInt() ?? 0,
        timestamp: (j['t'] as num?)?.toInt() ?? 0,
      );
}

class LeaderboardGame {
  final String id;
  final String name;
  final String scoreLabel;

  const LeaderboardGame({
    required this.id,
    required this.name,
    required this.scoreLabel,
  });
}
