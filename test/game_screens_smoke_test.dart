import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quirkade/core/theme/game_theme.dart';
import 'package:quirkade/features/chess/ui/chess_game_screen.dart';
import 'package:quirkade/features/connect4/ui/connect4_screen.dart';
import 'package:quirkade/features/dots_boxes/ui/dots_boxes_screen.dart';
import 'package:quirkade/features/game_2048/ui/game_2048_screen.dart';
import 'package:quirkade/features/heads_up/ui/heads_up_screen.dart';
import 'package:quirkade/features/ludo/ui/ludo_game_screen.dart';
import 'package:quirkade/features/memory/ui/memory_game_screen.dart';
import 'package:quirkade/features/pacman/ui/pacman_screen.dart';
import 'package:quirkade/features/quiz/ui/quiz_screen.dart';
import 'package:quirkade/features/simon/ui/simon_screen.dart';
import 'package:quirkade/features/snake/ui/snake_game_screen.dart';
import 'package:quirkade/features/stack/ui/stack_screen.dart';
import 'package:quirkade/features/sudoku/ui/sudoku_screen.dart';
import 'package:quirkade/features/tetris/ui/tetris_screen.dart';
import 'package:quirkade/features/tictactoe/ui/tictactoe_screen.dart';
import 'package:quirkade/features/wordle/ui/wordle_screen.dart';
import 'package:quirkade/features/wordle/data/word_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Ludo requires the exact final step into center home', () {
    expect(55 + 1, isNot(ludoFinishPosition));
    expect(56 + 1, ludoFinishPosition);
    expect(canAdvanceLudoPiece(56, 1), isTrue);
    expect(canAdvanceLudoPiece(56, 2), isFalse);
  });

  test('Ludo stacked pieces receive distinct visual offsets', () {
    final twoPieceOffsets = [
      ludoStackOffset(0, 2, 30),
      ludoStackOffset(1, 2, 30),
    ];
    expect(twoPieceOffsets.toSet(), hasLength(2));

    final fourPieceOffsets = List.generate(
      4,
      (index) => ludoStackOffset(index, 4, 30),
    );
    expect(fourPieceOffsets.toSet(), hasLength(4));
  });

  test('Ludo two-player colors always use opposite corners', () {
    expect(ludoOppositeColor(LudoColor.red), LudoColor.yellow);
    expect(ludoOppositeColor(LudoColor.yellow), LudoColor.red);
    expect(ludoOppositeColor(LudoColor.green), LudoColor.blue);
    expect(ludoOppositeColor(LudoColor.blue), LudoColor.green);
  });

  test('Five Letters only contains playable five-letter answers', () {
    expect(wordleAnswers, isNotEmpty);
    expect(wordleAnswers.every((word) => word.length == 5), isTrue);
    expect(wordleAnswers.toSet(), hasLength(wordleAnswers.length));
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final screens = <String, Widget>{
    '2048': const Game2048Screen(),
    'Snake': const SnakeGameScreen(),
    'Chess': const ChessGameScreen(),
    'Ludo': const LudoGameScreen(),
    'Tic Tac Toe': const TicTacToeScreen(),
    'Memory': const MemoryGameScreen(),
    'Four in a Row': const Connect4Screen(),
    'Sudoku': const SudokuScreen(),
    'Color Recall': const SimonScreen(),
    'Dots & Boxes': const DotsBoxesScreen(),
    'Quiz': const QuizScreen(),
    'Five Letters': const WordleScreen(),
    'Falling Blocks': const TetrisScreen(),
    'Maze Munch': const PacManScreen(),
    'Stack': const StackGameScreen(),
    'Guess It': const HeadsUpScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} opens without Flutter errors', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(theme: GameTheme.darkTheme, home: entry.value),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
    });
  }

  testWidgets('Guess It opens in landscape without Flutter errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: GameTheme.darkTheme, home: const HeadsUpScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('2048 adapts to a short wide window without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(790, 630);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: GameTheme.darkTheme, home: const Game2048Screen()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Swipe to move tiles'), findsOneWidget);
  });

  testWidgets('Ludo can leave during a dice roll without stale callbacks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: GameTheme.darkTheme, home: const LudoGameScreen()),
    );
    await tester.tap(find.text('1 Player'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Red'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('1 Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
