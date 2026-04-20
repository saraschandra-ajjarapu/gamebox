import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/leaderboard_service.dart';
import '../../../core/theme/game_theme.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  int _selectedIndex = 0;
  List<LeaderboardEntry> _entries = [];
  bool _loading = true;
  String _playerName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final game = LeaderboardService.allGames[_selectedIndex];
    final entries = await LeaderboardService.getTop(game.id);
    final name = await LeaderboardService.getLastName();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _playerName = name;
      _loading = false;
    });
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _playerName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.surface,
        title: const Text('Your name',
            style: TextStyle(color: GameTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 14,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: GameTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(color: GameTheme.textSecondary),
            counterText: '',
          ),
          onSubmitted: (_) =>
              Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save',
                  style: TextStyle(color: GameTheme.accent))),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      await LeaderboardService.saveLastName(newName);
      if (!mounted) return;
      setState(() => _playerName = newName);
    }
  }

  Future<void> _confirmClear() async {
    final game = LeaderboardService.allGames[_selectedIndex];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GameTheme.surface,
        title: Text('Clear ${game.name} scores?',
            style: const TextStyle(color: GameTheme.textPrimary)),
        content: const Text(
          'This removes all local scores for this game. This cannot be undone.',
          style: TextStyle(color: GameTheme.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear',
                  style: TextStyle(color: GameTheme.accentAlt))),
        ],
      ),
    );
    if (confirm == true) {
      await LeaderboardService.clear(game.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = LeaderboardService.allGames[_selectedIndex];
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('Leaderboard'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: GameTheme.accentAlt),
              tooltip: 'Clear scores for this game',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _editName();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: GameTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GameTheme.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_rounded,
                        color: GameTheme.accent, size: 20),
                    const SizedBox(width: 10),
                    const Text('Playing as: ',
                        style: TextStyle(
                            fontSize: 13,
                            color: GameTheme.textSecondary)),
                    Expanded(
                      child: Text(
                        _playerName.isEmpty ? 'Tap to set name' : _playerName,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _playerName.isEmpty
                                ? GameTheme.textSecondary
                                : GameTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.edit_rounded,
                        color: GameTheme.textSecondary, size: 16),
                  ]),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: LeaderboardService.allGames.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final g = LeaderboardService.allGames[i];
                  final selected = i == _selectedIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedIndex = i);
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? GameTheme.accent
                            : GameTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected
                                ? GameTheme.accent
                                : GameTheme.border),
                      ),
                      child: Center(
                        child: Text(
                          g.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white
                                  : GameTheme.textPrimary),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: GameTheme.accent))
                  : _entries.isEmpty
                      ? _empty(game)
                      : _list(game),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(LeaderboardGame game) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 80, color: GameTheme.textSecondary),
            const SizedBox(height: 16),
            Text('No scores yet for ${game.name}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: GameTheme.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              'Play the game — your best scores appear here with your name.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GameTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(LeaderboardGame game) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _entries.length,
      itemBuilder: (ctx, i) {
        final e = _entries[i];
        final rank = i + 1;
        final medal = rank == 1
            ? '🥇'
            : rank == 2
                ? '🥈'
                : rank == 3
                    ? '🥉'
                    : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: GameTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: rank <= 3 ? GameTheme.gold : GameTheme.border,
                width: rank <= 3 ? 1.5 : 1),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: medal != null
                    ? Text(medal, style: const TextStyle(fontSize: 24))
                    : Text('#$rank',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: GameTheme.textSecondary)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.name,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GameTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${e.score}',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: GameTheme.accent),
              ),
              const SizedBox(width: 6),
              Text(
                game.scoreLabel.toLowerCase(),
                style: const TextStyle(
                    fontSize: 11, color: GameTheme.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}
