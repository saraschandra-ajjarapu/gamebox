import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Owns the app's only ad format: an explicitly requested rewarded video.
/// No banner, interstitial, app-open, or automatic ad is loaded or displayed.
class RewardedAdService {
  RewardedAdService._();

  static final instance = RewardedAdService._();

  static const _androidProductionId = String.fromEnvironment(
    'ADMOB_ANDROID_REWARDED_ID',
    defaultValue: 'ca-app-pub-3095968893828878/9688297065',
  );
  static const _iosProductionId = String.fromEnvironment(
    'ADMOB_IOS_REWARDED_ID',
    defaultValue: 'ca-app-pub-3095968893828878/1346772614',
  );

  static const _androidTestId = 'ca-app-pub-3940256099942544/5224354917';
  static const _iosTestId = 'ca-app-pub-3940256099942544/1712485313';

  final isReady = ValueNotifier<bool>(false);
  RewardedAd? _ad;
  bool _initialized = false;
  bool _loading = false;
  bool _canRequestAds = false;

  /// Whether the SDK is initialized and consent permits ad requests.
  ///
  /// Other ad surfaces (the home banner) gate on this instead of repeating the
  /// consent flow — the UMP form must be shown once, not once per format.
  bool get canRequestAds => _canRequestAds;

  String get _adUnitId {
    if (Platform.isAndroid) {
      return kReleaseMode ? _androidProductionId : _androidTestId;
    }
    return kReleaseMode ? _iosProductionId : _iosTestId;
  }

  Future<void> initialize() async {
    if (_initialized || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    _initialized = true;

    // A release without configured production IDs must never request test ads.
    if (_adUnitId.isEmpty) {
      debugPrint('Rewarded ads disabled: production ad unit ID is missing.');
      return;
    }

    final consentUpdated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => consentUpdated.complete(),
      (error) {
        debugPrint('Consent information update failed: $error');
        consentUpdated.complete();
      },
    );
    await consentUpdated.future;
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) debugPrint('Consent form error: $error');
    });
    if (!await ConsentInformation.instance.canRequestAds()) return;
    _canRequestAds = true;

    // Cap every ad request at G — content suitable for general audiences,
    // including families. Without this AdMob is free to serve up to its
    // account default, which can include T and MA (mature) creatives:
    // gambling, dating, alcohol. Quirkade is rated 4+ and played by children,
    // so an 18+ creative appearing between rounds of Snake would be a real
    // problem regardless of what the store rating says.
    //
    // Deliberately NOT setting tagForChildDirectedTreatment. That is a COPPA
    // declaration that the app is directed at children; this app is published
    // as a general-audience title (isOrEverWasMadeForKids is false on the App
    // Store), so claiming otherwise here would contradict the store listing.
    // maxAdContentRating is the correct control for "no adult creatives" and
    // does not disable personalized ads for adults.
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(maxAdContentRating: MaxAdContentRating.g),
    );
    await MobileAds.instance.initialize();
    _load();
  }

  void _load() {
    if (_loading || _ad != null || _adUnitId.isEmpty) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
          isReady.value = true;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          isReady.value = false;
          debugPrint('Rewarded ad failed to load: $error');
        },
      ),
    );
  }

  /// Returns true only when the SDK confirms the user earned the reward.
  Future<bool> show() async {
    final ad = _ad;
    if (ad == null) {
      _load();
      return false;
    }

    _ad = null;
    isReady.value = false;
    final result = Completer<bool>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!result.isCompleted) result.complete(earned);
        _load();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!result.isCompleted) result.complete(false);
        _load();
      },
    );
    ad.show(onUserEarnedReward: (_, __) => earned = true);
    return result.future;
  }
}
