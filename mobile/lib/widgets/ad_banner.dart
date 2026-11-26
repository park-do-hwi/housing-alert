import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 광고 단위 ID. 빌드할 때 `--dart-define=ADMOB_BANNER_HOME=...` 처럼 넣는다.
/// 값이 없으면 구글이 제공하는 테스트 광고를 보여 준다 (실제 수익 없음, 정책 위반 아님).
const _testBanner = 'ca-app-pub-3940256099942544/9214589741';
const adUnitHome = String.fromEnvironment('ADMOB_BANNER_HOME', defaultValue: _testBanner);
const adUnitDetail = String.fromEnvironment('ADMOB_BANNER_DETAIL', defaultValue: _testBanner);

/// 광고를 켜고 끄는 스위치. `--dart-define=ADS_ENABLED=false` 로 끌 수 있다.
const adsEnabled = bool.fromEnvironment('ADS_ENABLED', defaultValue: true);

/// 동의창 시험용: 디버그 빌드에서 `--dart-define=UMP_TEST_DEVICE=<기기 해시>` 를 주면
/// 그 기기를 유럽(EEA)에 있는 것처럼 다룬다. 출시 빌드에서는 무시된다.
const _umpTestDevice = String.fromEnvironment('UMP_TEST_DEVICE');

class AdService {
  static bool _started = false;
  static bool _sdkStarted = false;

  /// 광고를 요청해도 되는 상태(동의가 필요 없거나, 동의 절차를 마침)면 true.
  static final ready = ValueNotifier<bool>(false);

  /// 앱 시작 때 한 번 부른다. 안드로이드에서만 동작한다.
  /// 유럽(EEA)·영국·스위스에서는 광고 전에 Google 동의창(UMP)을 먼저 보여 준다.
  static Future<void> init() async {
    if (_started || !adsEnabled || !Platform.isAndroid) return;
    _started = true;
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(
          consentDebugSettings: kDebugMode && _umpTestDevice.isNotEmpty
              ? ConsentDebugSettings(
                  debugGeography: DebugGeography.debugGeographyEea,
                  testIdentifiers: [_umpTestDevice],
                )
              : null,
        ),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          } finally {
            done.complete();
          }
        },
        (_) => done.complete(), // 확인에 실패해도 지난 실행의 동의 상태는 아래에서 쓴다
      );
      // 지난번에 이미 동의 절차를 마쳤다면 새 확인을 기다리지 않고 광고를 준비한다.
      await _startIfAllowed();
      await done.future;
      await _startIfAllowed();
    } catch (_) {
      _started = false;
    }
  }

  /// 설정 화면의 '광고 개인정보 설정' 버튼을 보여야 하는지.
  static Future<bool> privacyOptionsRequired() async {
    if (!adsEnabled || !Platform.isAndroid) return false;
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// 동의 선택을 다시 바꾸는 창을 연다.
  static Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((_) {});
    await _startIfAllowed();
  }

  static Future<void> _startIfAllowed() async {
    if (!await ConsentInformation.instance.canRequestAds()) return;
    if (_sdkStarted) return;
    _sdkStarted = true;
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.t),
      );
      await MobileAds.instance.initialize();
      ready.value = true;
    } catch (_) {
      _sdkStarted = false;
    }
  }
}

/// 화면 너비에 맞춰 크기가 정해지는 배너 광고. 광고를 못 받으면 자리도 차지하지 않는다.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, required this.unitId});
  final String unitId;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  int _width = 0;
  bool _loaded = false;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _load(int width) async {
    _width = width;
    _ad?.dispose();
    _ad = null;
    _loaded = false;
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted || width != _width) return;
    final ad = BannerAd(
      adUnitId: widget.unitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!adsEnabled || !Platform.isAndroid) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: AdService.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth.truncate();
            if (w > 0 && w != _width) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _load(w);
              });
            }
            final ad = _ad;
            if (!_loaded || ad == null) return const SizedBox.shrink();
            return Semantics(
              label: '광고',
              child: SizedBox(
                width: ad.size.width.toDouble(),
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            );
          },
        );
      },
    );
  }
}
