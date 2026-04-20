import 'package:flutter/material.dart';
import '../../../core/theme/game_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.background,
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: GameTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset('assets/app_icon.png',
                          width: 96, height: 96, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 14),
                    const Text('GameBox',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: GameTheme.textPrimary,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    const Text('Classic Games. One App.',
                        style: TextStyle(
                            fontSize: 14, color: GameTheme.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _section(
                title: 'What is GameBox?',
                body:
                    'GameBox is a collection of timeless games — all in one app, '
                    'all offline, all free to play. Think of it as a box you can '
                    'open anytime for a quick round of your favourites.',
              ),
              _section(
                title: 'Our promise',
                body:
                    '• No accounts, no sign-ups — just play.\n'
                    '• Everything runs offline on your device.\n'
                    '• High scores and leaderboards stay on your phone — nothing leaves it.\n'
                    '• Ads (if any) never interrupt a game in progress.\n'
                    '• New games added over time.',
              ),
              _section(
                title: 'How the leaderboard works',
                body:
                    'Each game keeps a local top-10 list with player names. '
                    'When you beat a top score, the game asks for your name — perfect for '
                    'sharing the same phone with friends or family.',
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Made with \u2764 for classic game lovers',
                  style: TextStyle(
                      fontSize: 13,
                      color: GameTheme.textSecondary.withValues(alpha: 0.8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GameTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GameTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GameTheme.accent)),
          const SizedBox(height: 8),
          Text(body,
              style: const TextStyle(
                  fontSize: 14, height: 1.5, color: GameTheme.textPrimary)),
        ],
      ),
    );
  }
}
