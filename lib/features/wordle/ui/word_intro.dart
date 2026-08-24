import 'package:flutter/material.dart';
import '../../../core/theme/game_theme.dart';
import '../data/topic_words.dart';

const _correct = Color(0xFF538D4E);
const _present = Color(0xFFB59F3B);
const _absent = Color(0xFF3A3A3C);

/// One example tile, used to teach the colours by showing them.
class _ExampleTile extends StatelessWidget {
  const _ExampleTile(this.letter, this.color);

  final String letter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
    );
  }
}

Widget _exampleRow(String word, List<Color> colors, String explanation) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (int i = 0; i < word.length; i++)
              _ExampleTile(word[i], colors[i]),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          explanation,
          style: const TextStyle(
            color: GameTheme.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

/// Teach the game by playing a round of it on paper.
///
/// The old help was a wall of prose behind a '?' icon in the app bar, and the
/// feedback was that people opened the game, did not understand what the
/// colours meant, and skipped it. Three worked rows say the same thing in
/// about four seconds.
Future<void> showHowToPlayWord(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: GameTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: GameTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'How to play',
              style: TextStyle(
                color: GameTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pick a topic, then find the hidden word. After every guess the '
              'tiles change colour to tell you how close you were.',
              style: TextStyle(
                color: GameTheme.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Say the topic is Cricket and the word is PITCH.',
              style: TextStyle(
                color: GameTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _exampleRow(
              'CATCH',
              const [_absent, _absent, _correct, _correct, _correct],
              'Green means the letter is right and in the right place. '
                  'T, C and H are exactly where they belong.',
            ),
            _exampleRow(
              'SPINS',
              const [_absent, _present, _present, _absent, _absent],
              'Yellow means the letter is in the word but somewhere else. '
                  'P and I belong further along.',
            ),
            _exampleRow('PITCH', const [
              _correct,
              _correct,
              _correct,
              _correct,
              _correct,
            ], 'All green — you got it.'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GameTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good to know',
                    style: TextStyle(
                      color: GameTheme.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Any word of the right length is accepted — guess freely.\n'
                    '• The topic and the number of letters are shown above the grid.\n'
                    '• Stuck? The 💡 button reveals a letter, twice a game.',
                    style: TextStyle(
                      color: GameTheme.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: GameTheme.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Got it',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Choose what the answer is about.
///
/// Returns null if the sheet is dismissed without choosing, which leaves the
/// round already in progress alone.
Future<WordTopic?> showTopicPicker(BuildContext context, WordTopic current) {
  return showModalBottomSheet<WordTopic>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: GameTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: GameTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    'Pick a topic',
                    style: TextStyle(
                      color: GameTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'The hidden word will come from whatever you choose.',
                  style: TextStyle(
                    color: GameTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: GridView.count(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              shrinkWrap: true,
              children: [
                for (final topic in wordTopics)
                  _TopicCard(
                    topic: topic,
                    selected: topic.id == current.id,
                    onTap: () => Navigator.pop(ctx, topic),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final WordTopic topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? GameTheme.accent.withValues(alpha: 0.18)
          : GameTheme.surfaceLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? GameTheme.accent : GameTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(topic.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.name,
                      style: TextStyle(
                        color: selected
                            ? GameTheme.accent
                            : GameTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${topic.words.length} words',
                      style: const TextStyle(
                        color: GameTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
