import 'package:flutter/material.dart';

import '../services/rewarded_ad_service.dart';

/// The "Watch ad to continue" button shown on a game-over screen.
///
/// Every game that offers a rewarded continue renders this, so the wording,
/// the disabled state and the once-per-game rule stay identical everywhere.
/// It was copied by hand into Snake and Falling Blocks first; extracting it
/// keeps the next five games from drifting apart.
///
/// Renders nothing unless the game is actually over and the continue has not
/// been used yet. When AdMob has no ad loaded the button stays visible but
/// disabled and says so, rather than vanishing — a button that disappears
/// reads as a bug, and the app is not yet earning enough fill to rely on one
/// always being ready.
class RewardedContinueButton extends StatelessWidget {
  const RewardedContinueButton({
    super.key,
    required this.gameOver,
    required this.alreadyUsed,
    required this.onContinue,
    this.label = 'Watch ad to continue',
  });

  final bool gameOver;
  final bool alreadyUsed;
  final Future<void> Function() onContinue;

  /// Overridable so a game can name what the continue actually grants,
  /// e.g. "Watch ad for an extra life".
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!gameOver || alreadyUsed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ValueListenableBuilder<bool>(
        valueListenable: RewardedAdService.instance.isReady,
        builder: (context, ready, _) => OutlinedButton.icon(
          onPressed: ready ? onContinue : null,
          icon: const Icon(Icons.ondemand_video_rounded),
          label: Text(ready ? label : 'Continue ad unavailable'),
        ),
      ),
    );
  }
}
