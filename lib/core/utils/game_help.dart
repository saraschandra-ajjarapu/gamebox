import 'package:flutter/material.dart';
import '../theme/game_theme.dart';

/// Game instructions data and help dialog utility
class GameHelp {
  static const Map<String, String> instructions = {
    'Chess': '''
Each player starts with 16 pieces: 1 King, 1 Queen, 2 Rooks, 2 Bishops, 2 Knights, and 8 Pawns.

- Pawns move forward 1 square (2 on first move), capture diagonally
- Rooks move in straight lines (horizontal/vertical)
- Knights move in an L-shape and can jump over pieces
- Bishops move diagonally
- Queen moves in any direction
- King moves 1 square in any direction

Goal: Checkmate your opponent's King so it cannot escape capture.''',

    'Ludo': '''
Each player has 4 tokens in their base.

- Roll a 6 to bring a token out of base
- Move tokens clockwise around the board by dice value
- Land on an opponent's token to send it back to base
- Safe spots (marked) protect tokens from capture
- Roll a 6, capture a token, or reach home to get an extra turn
- First player to get all 4 tokens home wins!''',

    '2048': '''
Swipe in any direction to move all tiles.

- Tiles with the same number merge when they collide
- Each merge adds to your score
- A new tile (2 or 4) appears after each move
- Goal: Create a 2048 tile!
- Game ends when no moves are possible

Tip: Keep your highest tile in a corner.''',

    'Snake': '''
Guide the snake to eat food and grow longer.

- Swipe to change direction
- Eating food scores 10 points and grows the snake
- Speed increases every 30 points
- Don't hit your own tail!

Special Foods (appear randomly after 30 points):
- Fake food — vanishes when you get close!
- Rock vs Real — two foods appear, one is real (+20 pts), the other is a rock (snake shakes head, no harm)
- Timed star — bonus food with countdown timer, more points for eating quickly

Goal: Get the highest score possible.''',

    'Sudoku': '''
Fill the 9x9 grid with numbers 1-9.

Rules:
- Each row must contain 1-9 (no repeats)
- Each column must contain 1-9 (no repeats)
- Each 3x3 box must contain 1-9 (no repeats)

- Tap a cell, then tap a number to place it
- Use notes to track possible numbers
- Pre-filled numbers cannot be changed''',

    'Tic Tac Toe': '''
Take turns placing X or O on the 3x3 grid.

- First player uses X, second uses O
- Get 3 in a row (horizontal, vertical, or diagonal) to win
- If all 9 squares are filled with no winner, it's a draw

Tip: Take the center square when possible!''',

    'Memory': '''
Find all matching pairs of cards.

- Tap a card to flip it over
- Tap a second card to try matching
- If they match, they stay face up
- If not, both flip back after a moment
- Find all pairs to win!

Fewer moves = better score.''',

    'Connect 4': '''
Drop colored discs into a 7-column, 6-row grid.

- Players take turns dropping one disc
- Discs fall to the lowest available position
- First to connect 4 discs in a row wins!
- Connections can be horizontal, vertical, or diagonal

Tip: Watch for your opponent's setups while building your own.''',

    'Simon Says': '''
Follow the pattern of colored buttons.

- Watch the sequence of lights carefully
- Repeat the pattern by tapping buttons in order
- Each round adds one more step
- One mistake and the game is over!

The sequence gets longer each round. How far can you go?''',

    'Wordle': '''
Guess the 5-letter word in 6 tries!

- Type a 5-letter word and press ENTER
- Tiles change color after each guess:
  - Green = correct letter, correct position
  - Yellow = correct letter, wrong position
  - Gray = letter not in the word
- The keyboard updates to show which letters you've used

Tips:
- Start with words that use common letters (E, A, R, S, T)
- Avoid reusing gray letters
- Use yellow letters in different positions

Stats track your win streak and win rate across games.''',

    'Quiz': '''
Test your knowledge across 8 fun categories!

Modes:
- Solo — answer 10 questions against a timer (15 sec each)
- Pass & Play — 2-4 players on the same device, take turns
- WiFi Multiplayer — 2-4 players on the same WiFi network

How to play:
- Read the question and tap your answer
- Faster answers earn bonus points
- Each correct answer = 10 pts + time bonus
- Wrong answer or timeout = 0 pts

WiFi Multiplayer:
- One player taps "Host Game" and shares the room code
- Other players tap "Join Game" and enter the code
- All players must be on the same WiFi network
- Up to 4 players can join!

Categories: Science, Geography, Universal Facts, Friends TV Series, Cricket, Countries & Capitals, Telugu Movies, Know India, or Random mix.''',

    'Dots & Boxes': '''
Take turns drawing lines between dots.

- Tap between two dots to draw a line
- Complete the 4th side of a box to claim it
- Claiming a box earns an extra turn
- The player with the most boxes wins!

Tip: Avoid drawing the 3rd side of a box — your opponent will take it.''',

    'Tetris': '''
Stack falling tetrominoes and clear full horizontal lines.

Controls (swipe):
- Swipe left/right — move piece
- Swipe down — soft drop (+1 pt per row)
- Swipe up — hard drop (+2 pts per row)
- Tap — rotate

Or toggle the D-Pad in the top bar for buttons.

Scoring (multiplied by level):
- 1 line = 40, 2 = 100, 3 = 300, 4 (Tetris!) = 1200
- Every 10 lines raises the level — speed increases.

Tips:
- Keep one column open and save I-pieces for Tetrises.
- The dim ghost shows where the piece will land.''',

    'Stack': '''
Stack blocks as high as you can.

- A block slides back and forth above the tower
- Tap anywhere to drop it onto the tower below
- Any part hanging over the edge is trimmed away — the next block is only as wide as what remains
- Miss the tower entirely → game over

Tips:
- Watch the sliding rhythm — tap a fraction of a beat before center
- A PERFECT drop (aligned within a hair) keeps the full width and builds a streak
- Speed rises steadily — stay relaxed''',

    'Headsup!': '''
Pass-and-play party game — also known as Dumb Charades.

Setup:
- Enter team names and pick a color for each (2–4 teams)
- Choose category: English Words, Telugu Movies, Hindi Movies, or All Mix
- Pick points to win (10/15/20/25) and time per round (30s–3 min)

How to play:
- One player from the active team holds the phone to their forehead
- Their teammates see the word and act it out or describe it (no saying the word)
- Tap CORRECT (or swipe right/down) when they guess — SKIP (or swipe left/up) to pass
- When the timer runs out, the team's score goes up by correct answers

Winning:
- First team to reach the target points wins!

Screen works in portrait or landscape — whichever feels natural on the forehead.''',

    'Pac-Man': '''
Eat every dot in the maze while avoiding ghosts.

Controls:
- Swipe in any direction to turn
- Or toggle the D-Pad for buttons

Rules:
- Small dots = 10 pts
- Power pellets (big dots) = 50 pts and scare all ghosts briefly — eat them for bonus points
- Bonus fruit (🍒) appears once per wave after half the dots are eaten — +100 pts if you grab it before it disappears
- Ghosts respawn at the center house
- Clear all dots to win the wave; each wave uses a different maze

Waves:
1. Classic
2. Cross Quarters
3. Open Plaza
(rotates)

Tip: Use the tunnel edges to escape when a ghost closes in.''',
  };

  static void show(BuildContext context, String gameName) {
    final text = instructions[gameName] ?? 'No instructions available.';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: GameTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: GameTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const Icon(Icons.help_outline_rounded,
                    color: GameTheme.accent, size: 22),
                  const SizedBox(width: 10),
                  Text('How to Play $gameName',
                    style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: GameTheme.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close_rounded,
                      color: GameTheme.textSecondary, size: 22),
                  ),
                ],
              ),
            ),
            const Divider(color: GameTheme.border, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Text(text,
                  style: const TextStyle(
                    fontSize: 15, color: GameTheme.textPrimary,
                    height: 1.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
