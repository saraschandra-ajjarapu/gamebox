import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirkade/core/widgets/rewarded_continue_button.dart';

/// Games that offer a rewarded continue. Adding a game here without wiring it
/// fails the contract test below.
const gamesWithContinue = <String, String>{
  'Snake': 'lib/features/snake/ui/snake_game_screen.dart',
  'Falling Blocks': 'lib/features/tetris/ui/tetris_screen.dart',
  'Maze Munch': 'lib/features/pacman/ui/pacman_screen.dart',
  'Stack': 'lib/features/stack/ui/stack_screen.dart',
  'Color Recall': 'lib/features/simon/ui/simon_screen.dart',
};

void main() {
  group('rewarded continue button', () {
    testWidgets('hidden until the game is actually over', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RewardedContinueButton(
              gameOver: false,
              alreadyUsed: false,
              onContinue: () async {},
            ),
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('hidden once the continue has been used', (tester) async {
      // One continue per game. Without this a player could keep paying ads to
      // extend a single run indefinitely, which makes the leaderboard
      // meaningless.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RewardedContinueButton(
              gameOver: true,
              alreadyUsed: true,
              onContinue: () async {},
            ),
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('shown but disabled when no ad has loaded', (tester) async {
      // AdMob fill is limited for a newly published app, so "no ad ready" is
      // the common case. The button must explain itself rather than vanish.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RewardedContinueButton(
              gameOver: true,
              alreadyUsed: false,
              onContinue: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Continue ad unavailable'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
    });
  });

  group('every game that offers a continue wires it the same way', () {
    for (final entry in gamesWithContinue.entries) {
      test('${entry.key} uses the shared button and the once-per-game flag', () {
        final source = File(entry.value).readAsStringSync();
        expect(
          source,
          contains('RewardedContinueButton('),
          reason: '${entry.key} must render the shared button',
        );
        expect(
          source,
          contains('_usedRewardedContinue'),
          reason: '${entry.key} must track the once-per-game flag',
        );
        // The guard is what stops a second continue in the same run.
        expect(
          source,
          contains('if (_usedRewardedContinue || !_gameOver) return;'),
          reason: '${entry.key} must guard its continue handler',
        );
        // A fresh game must clear the flag, otherwise the second run of a
        // session silently loses its continue.
        expect(
          source,
          contains('_usedRewardedContinue = false;'),
          reason: '${entry.key} must reset the flag when a new game starts',
        );
      });
    }
  });
}
