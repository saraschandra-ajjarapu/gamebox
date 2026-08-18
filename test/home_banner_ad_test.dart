import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirkade/core/widgets/home_banner_ad.dart';

void main() {
  test('production banner IDs have no default, so release ships dark', () {
    // Tests run in debug, where adUnitId correctly resolves to Google's test
    // unit — so assert the invariant at the source instead: the production
    // constants must have NO defaultValue. If one were given a test ID as its
    // default, a release build would serve Google's test creatives to real
    // users, which looks like a broken app and earns nothing.
    final source =
        File('lib/core/widgets/home_banner_ad.dart').readAsStringSync();
    for (final key in ['ADMOB_ANDROID_BANNER_ID', 'ADMOB_IOS_BANNER_ID']) {
      final decl = RegExp(
        r"String\.fromEnvironment\(\s*'" + key + r"',([^)]*)\)",
      ).firstMatch(source);
      expect(decl, isNotNull, reason: '$key must be a dart-define');
      expect(
        decl!.group(1),
        isNot(contains('defaultValue')),
        reason: '$key must default to empty so release ships dark',
      );
    }
  });

  testWidgets('renders nothing until an ad actually loads', (tester) async {
    // No SDK in a widget test, so nothing can load. The banner must collapse
    // to zero height rather than reserve a permanent grey gap under the game
    // grid — fill is limited for a newly published app, so "no ad" is the
    // ordinary case on real devices too.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeBannerAd())),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(HomeBannerAd)), Size.zero);
  });

  test('no game screen renders the banner', () {
    // The App Store listing states "No disruptive ads during active gameplay".
    // The banner belongs on home, leaderboard and about only; this pins that
    // no game screen ever imports or renders it.
    final gameScreens = Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .expand((d) => Directory('${d.path}/ui').existsSync()
            ? Directory('${d.path}/ui').listSync().whereType<File>()
            : <File>[])
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains('/home/'))
        .where((f) => !f.path.contains('/leaderboard/'))
        .where((f) => !f.path.contains('/about/'));

    for (final f in gameScreens) {
      expect(
        f.readAsStringSync().contains('HomeBannerAd'),
        isFalse,
        reason: '${f.path} must not show a banner',
      );
    }
  });
}
