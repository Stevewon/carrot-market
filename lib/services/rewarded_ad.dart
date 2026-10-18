import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 구글 보상형 광고 한 편 — 끝까지 봐서 보상을 받으면 true, 닫거나 못 불러오면 false.
/// [userId]·[customData] 는 AdMob 서버 확인(SSV) 콜백에 그대로 실려 서버가 누구의 어느 꽝인지 안다.
class RewardedAds {
  static bool _ready = false;

  /// 테스트에서 광고 대신 바꿔 끼운다.
  @visibleForTesting
  static Future<bool> Function(String unitId, String userId, String customData)? override;

  static Future<bool> show(String unitId, {required String userId, required String customData}) async {
    if (override != null) return override!(unitId, userId, customData);
    if (!_ready) {
      await MobileAds.instance.initialize();
      _ready = true;
    }
    final loaded = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (e) {
          debugPrint('[ads] rewarded load failed: $e');
          loaded.complete(null);
        },
      ),
    );
    final ad = await loaded.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (ad == null) throw const RewardedAdUnavailable();

    ad.setServerSideOptions(ServerSideVerificationOptions(userId: userId, customData: customData));
    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        debugPrint('[ads] rewarded show failed: $e');
        a.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future;
  }
}

/// 광고를 불러오지 못했다 (네트워크·광고 없음). 사용자는 잠시 뒤 다시 시도하거나 QTA 를 낼 수 있다.
class RewardedAdUnavailable implements Exception {
  const RewardedAdUnavailable();
}
