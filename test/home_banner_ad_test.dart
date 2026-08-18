import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirkade/core/widgets/home_banner_ad.dart';

void main() {
  test('production banner units are real, never Google test units', () {
    // Tests run in debug, where adUnitId correctly resolves to Google's test
    // unit — so assert the invariant at the source instead.
    //
    // The IDs are hardcoded defaults rather than required dart-defines, so a
    // build that forgets a flag cannot silently ship the banner dark. The risk
    // that swaps in for that one is a test unit reaching production, which
    // would serve "Test Ad" creatives to real users and earn nothing.
    const googleTestPublisher = '3940256099942544';
    const ourPublisher = '3095968893828878';
    final source =
        File('lib/core/widgets/home_banner_ad.dart').readAsStringSync();

    for (final key in ['ADMOB_ANDROID_BANNER_ID', 'ADMOB_IOS_BANNER_ID']) {
      final decl = RegExp(
        r"String\.fromEnvironment\(\s*'" + key + r"',(.*?)\);",
        dotAll: true,
      ).firstMatch(source);
      expect(decl, isNotNull, reason: '$key must be a dart-define');
      final body = decl!.group(1)!;
      expect(
        body,
        contains('defaultValue'),
        reason: '$key must default to a real unit, not ship dark',
      );
      expect(
        body,
        contains(ourPublisher),
        reason: '$key default must belong to our AdMob publisher',
      );
      expect(
        body,
        isNot(contains(googleTestPublisher)),
        reason: '$key must never default to a Google test unit',
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
