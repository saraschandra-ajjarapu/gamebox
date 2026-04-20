import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/leaderboard_service.dart';
import '../theme/game_theme.dart';

/// Show an "enter your name" dialog when a score qualifies for the leaderboard.
/// Returns the entered name (or null if dismissed — in which case we still save as Anonymous).
class HighScoreDialog {
  /// Call on game over. If score qualifies, prompts for name and records the entry.
  /// Returns true if score was recorded.
  static Future<bool> submitIfQualifies({
    required BuildContext context,
    required String gameId,
    required String gameName,
    required int score,
    String scoreLabel = 'Score',
  }) async {
    if (score <= 0) return false;
    final qualifies = await LeaderboardService.qualifies(gameId, score);
    if (!qualifies) return false;
    if (!context.mounted) return false;

    final last = await LeaderboardService.getLastName();
    if (!context.mounted) return false;

    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NameDialog(
        gameName: gameName,
        score: score,
        scoreLabel: scoreLabel,
        initialName: last,
      ),
    );

    final rank = await LeaderboardService.submit(
      gameId,
      name ?? 'Anonymous',
      score,
    );
    return rank >= 0;
  }
}

class _NameDialog extends StatefulWidget {
  final String gameName;
  final int score;
  final String scoreLabel;
  final String initialName;

  const _NameDialog({
    required this.gameName,
    required this.score,
    required this.scoreLabel,
    required this.initialName,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: GameTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, color: GameTheme.gold, size: 52),
            const SizedBox(height: 12),
            const Text('New High Score!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: GameTheme.textPrimary)),
            const SizedBox(height: 6),
            Text('${widget.gameName} • ${widget.scoreLabel}: ${widget.score}',
                style: const TextStyle(fontSize: 13, color: GameTheme.textSecondary)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 14,
              textCapitalization: TextCapitalization.words,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: GameTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter your name',
                hintStyle: const TextStyle(color: GameTheme.textSecondary),
                counterText: '',
                filled: true,
                fillColor: GameTheme.background,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: GameTheme.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: GameTheme.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: GameTheme.accent, width: 2)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GameTheme.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
