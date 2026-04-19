import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/game_help.dart';
import '../../game_2048/ui/game_2048_screen.dart';
import '../../snake/ui/snake_game_screen.dart';
import '../../chess/ui/chess_game_screen.dart';
import '../../tictactoe/ui/tictactoe_screen.dart';
import '../../ludo/ui/ludo_game_screen.dart';
import '../../memory/ui/memory_game_screen.dart';
import '../../connect4/ui/connect4_screen.dart';
import '../../sudoku/ui/sudoku_screen.dart';
import '../../simon/ui/simon_screen.dart';
import '../../dots_boxes/ui/dots_boxes_screen.dart';
import '../../quiz/ui/quiz_screen.dart';
import '../../wordle/ui/wordle_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header with logo
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset('assets/app_icon.png',
                            width: 48, height: 48, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        const Text('Plaayz',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                            color: GameTheme.textPrimary, letterSpacing: -0.5)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('GameBox — Fun Games',
                      style: TextStyle(fontSize: 15, color: GameTheme.textSecondary)),
                  ],
                ),
              ),
            ),

            // Games grid
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, childAspectRatio: 0.85,
                  crossAxisSpacing: 14, mainAxisSpacing: 14),
                delegate: SliverChildListDelegate([
                  _GameCard(title: '2048', subtitle: 'Slide & merge',
                    icon: Icons.grid_4x4_rounded, helpName: '2048',
                    gradient: const [Color(0xFFEDC53F), Color(0xFFE8A520)],
                    players: '1 Player',
                    onTap: () => _push(context, const Game2048Screen())),
                  _GameCard(title: 'Snake', subtitle: 'Classic arcade',
                    icon: Icons.timeline_rounded, helpName: 'Snake',
                    gradient: const [Color(0xFF4ECDC4), Color(0xFF2EAF9F)],
                    players: '1 Player',
                    onTap: () => _push(context, const SnakeGameScreen())),
                  _GameCard(title: 'Chess', subtitle: 'Battle of minds',
                    icon: Icons.castle_rounded, helpName: 'Chess',
                    gradient: const [Color(0xFF667EEA), Color(0xFF764BA2)],
                    players: '1-2 Players',
                    onTap: () => _push(context, const ChessGameScreen())),
                  _GameCard(title: 'Ludo', subtitle: 'Roll & race',
                    icon: Icons.casino_rounded, helpName: 'Ludo',
                    gradient: const [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                    players: '2-4 Players',
                    onTap: () => _push(context, const LudoGameScreen())),
                  _GameCard(title: 'Tic Tac Toe', subtitle: 'X vs O',
                    icon: Icons.tag_rounded, helpName: 'Tic Tac Toe',
                    gradient: const [Color(0xFFA8E063), Color(0xFF56AB2F)],
                    players: '1-2 Players',
                    onTap: () => _push(context, const TicTacToeScreen())),
                  _GameCard(title: 'Memory', subtitle: 'Find pairs',
                    icon: Icons.psychology_rounded, helpName: 'Memory',
                    gradient: const [Color(0xFFFF9A9E), Color(0xFFFF6B8A)],
                    players: '1 Player',
                    onTap: () => _push(context, const MemoryGameScreen())),
                  _GameCard(title: 'Connect 4', subtitle: 'Drop & win',
                    icon: Icons.circle_outlined, helpName: 'Connect 4',
                    gradient: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                    players: '1-2 Players',
                    onTap: () => _push(context, const Connect4Screen())),
                  _GameCard(title: 'Sudoku', subtitle: 'Number puzzle',
                    icon: Icons.grid_on_rounded, helpName: 'Sudoku',
                    gradient: const [Color(0xFF7B68EE), Color(0xFF5B4FCF)],
                    players: '1 Player',
                    onTap: () => _push(context, const SudokuScreen())),
                  _GameCard(title: 'Simon Says', subtitle: 'Memory colors',
                    icon: Icons.palette_rounded, helpName: 'Simon Says',
                    gradient: const [Color(0xFFE53935), Color(0xFF1E88E5)],
                    players: '1 Player',
                    onTap: () => _push(context, const SimonScreen())),
                  _GameCard(title: 'Dots & Boxes', subtitle: 'Claim squares',
                    icon: Icons.grid_4x4_rounded, helpName: 'Dots & Boxes',
                    gradient: const [Color(0xFFFF8A65), Color(0xFFFF5722)],
                    players: '1-2 Players',
                    onTap: () => _push(context, const DotsBoxesScreen())),
                  _GameCard(title: 'Quiz', subtitle: 'Test your knowledge',
                    icon: Icons.quiz_rounded, helpName: 'Quiz',
                    gradient: const [Color(0xFF7B68EE), Color(0xFFE040FB)],
                    players: '1-4 Players',
                    onTap: () => _push(context, const QuizScreen())),
                  _GameCard(title: 'Wordle', subtitle: 'Guess the word',
                    icon: Icons.abc_rounded, helpName: 'Wordle',
                    gradient: const [Color(0xFF538D4E), Color(0xFF3A6B35)],
                    players: '1 Player',
                    onTap: () => _push(context, const WordleScreen())),
                ]),
              ),
            ),

            // Coming soon card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [GameTheme.surface, GameTheme.surfaceLight.withValues(alpha: 0.5)]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: GameTheme.border)),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: GameTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.rocket_launch_rounded, color: GameTheme.accent, size: 28)),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('More games coming soon!',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                color: GameTheme.textPrimary)),
                            SizedBox(height: 2),
                            Text('Stay tuned for new additions',
                              style: TextStyle(fontSize: 13, color: GameTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _GameCard extends StatefulWidget {
  final String title, subtitle, players, helpName;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _GameCard({required this.title, required this.subtitle, required this.icon,
    required this.gradient, required this.players, required this.onTap,
    required this.helpName});

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); HapticFeedback.lightImpact(); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: widget.gradient),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: widget.gradient.first.withValues(alpha: 0.3),
              blurRadius: 16, offset: const Offset(0, 6))]),
          child: Stack(children: [
            Positioned(right: -15, bottom: -15,
              child: Icon(widget.icon, size: 100, color: Colors.white.withValues(alpha: 0.12))),
            Padding(padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Container(padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12)),
                      child: Icon(widget.icon, color: Colors.white, size: 26)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        GameHelp.show(context, widget.helpName);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.help_outline_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 3),
                            Text('How to Play',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                                color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                Text(widget.subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(widget.players, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white))),
              ])),
          ]),
        ),
      ),
    );
  }
}
