import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quirkade/core/services/leaderboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('higher scores rank first for score games', () async {
    await LeaderboardService.submit('2048', 'A', 100);
    await LeaderboardService.submit('2048', 'B', 300);
    final top = await LeaderboardService.getTop('2048');
    expect(top.map((e) => e.score), [300, 100]);
  });

  test('fewer moves rank first for Memory', () async {
    await LeaderboardService.submit('memory', 'A', 30);
    await LeaderboardService.submit('memory', 'B', 18);
    final top = await LeaderboardService.getTop('memory');
    expect(top.map((e) => e.score), [18, 30]);
  });
}
