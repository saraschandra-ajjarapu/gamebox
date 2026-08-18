import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/rewarded_ad_service.dart';

/// An anchored adaptive banner for non-gameplay screens.
///
/// Deliberately never rendered on a game screen. The App Store listing states
/// "No disruptive ads during active gameplay", so this appears only where the
/// player is choosing what to do next — the home grid, Leaderboards, About.
/// AdMob refreshes the creative on its own schedule, so one placement yields
/// rotating impressions without ever interrupting play.
///
/// Ships dark until real ad units exist: the production IDs default to empty,
/// and an empty ID renders nothing rather than falling back to test ads, which
/// would put Google's test creatives in front of real users.
class HomeBannerAd extends StatefulWidget {
  const HomeBannerAd({super.key});

  static const _androidProductionId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_ID',
  );
  static const _iosProductionId = String.fromEnvironment(
    'ADMOB_IOS_BANNER_ID',
  );

  // Google's own always-fill test units, used only in debug/profile so the
  // layout can be verified before real units exist.
  static const _androidTestId = 'ca-app-pub-3940256099942544/6300978111';
  static const _iosTestId = 'ca-app-pub-3940256099942544/2934735716';

  static String get adUnitId {
    if (Platform.isAndroid) {
      return kReleaseMode ? _androidProductionId : _androidTestId;
    }
    return kReleaseMode ? _iosProductionId : _iosTestId;
  }

  @override
  State<HomeBannerAd> createState() => _HomeBannerAdState();
}

class _HomeBannerAdState extends State<HomeBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Adaptive sizing needs the screen width, which is only available once
    // there is a MediaQuery — hence here rather than initState. Guarded so a
    // rebuild cannot start a second request for the same widget.
    if (!_requested) {
      _requested = true;
      _load();
    }
  }

  Future<void> _load() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (HomeBannerAd.adUnitId.isEmpty) return;
    // The rewarded service owns SDK init and the consent flow. Without an
    // accepted consent state a request would be dropped anyway.
    if (!RewardedAdService.instance.canRequestAds) return;

    final width = MediaQuery.sizeOf(context).width.truncate();
    final size =
        await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;

    final banner = BannerAd(
      size: size,
      adUnitId: HomeBannerAd.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // Fill is limited for a newly published app, so failing to load is
          // the ordinary case. Dispose and leave the slot collapsed.
          debugPrint('Banner failed to load: $error');
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _banner = null;
            _loaded = false;
          });
        },
      ),
    );
    _banner = banner;
    await banner.load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    // Collapse entirely until an ad is actually on screen. Reserving height
    // for an ad that may never arrive would leave a permanent grey gap under
    // the game grid on every device where fill is zero.
    if (!_loaded || banner == null) return const SizedBox.shrink();
    return SizedBox(
      width: banner.size.width.toDouble(),
      height: banner.size.height.toDouble(),
      child: AdWidget(ad: banner),
    );
  }
}
