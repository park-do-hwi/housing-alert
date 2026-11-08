import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'models.dart';

/// 푸시 알림(FCM 주제 구독). 서버·기기 등록 없이, 관심 지역·유형에 해당하는 주제만 구독한다.
/// 주제 이름 규칙은 server/app/topic_push.py 와 같다: n_<시·도 번호>_<유형 번호>, 못 찾으면 x.
abstract class PushService {
  Future<void> init();
  Future<void> sync(Subscription s);
}

class NoopPushService implements PushService {
  @override
  Future<void> init() async {}
  @override
  Future<void> sync(Subscription s) async {}
}

/// 구독 조건 → 주제 집합. 빈 목록은 "전체"(알 수 없는 값 x 포함).
Set<String> topicsFor(Subscription s) {
  final sidos = s.sido.isEmpty
      ? [for (var i = 0; i < sidoList.length; i++) '$i', 'x']
      : [
          for (final v in s.sido)
            if (sidoList.contains(v)) '${sidoList.indexOf(v)}',
        ];
  final cats = s.categories.isEmpty
      ? [for (var i = 0; i < categoryList.length; i++) '$i', 'x']
      : [
          for (final v in s.categories)
            if (categoryList.contains(v)) '${categoryList.indexOf(v)}',
        ];
  return {
    for (final a in sidos)
      for (final b in cats) 'n_${a}_$b',
  };
}

class FcmPushService implements PushService {
  FcmPushService(this._prefs, {this.onOpen});
  final SharedPreferences _prefs;

  /// 알림을 눌러 앱이 열렸을 때(id, url). 앱이 꺼져 있다가 열린 경우도 포함한다.
  final void Function(String id, String url)? onOpen;
  bool _ready = false;
  static const _key = 'fcm_topics';
  static const _askedKey = 'push_asked';

  /// 알림 권한을 아직 안 물어봤고 기기도 허용 여부를 정하지 않았으면 true (Android 13+ 첫 실행).
  Future<bool> needsAsk() async {
    if (!_ready || (_prefs.getBool(_askedKey) ?? false)) return false;
    try {
      final st = await FirebaseMessaging.instance.getNotificationSettings();
      return st.authorizationStatus == AuthorizationStatus.notDetermined;
    } catch (_) {
      return false;
    }
  }

  /// 설명 화면에서 사용자가 '받기'를 눌렀을 때 시스템 권한창을 띄운다. 한 번만 묻는다.
  Future<void> requestPermission() async {
    await _prefs.setBool(_askedKey, true);
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
  }

  Future<void> markAsked() => _prefs.setBool(_askedKey, true);

  @override
  Future<void> init() async {
    if (!Platform.isAndroid) return; // iOS 는 Firebase iOS 앱을 등록한 뒤에 켠다
    try {
      await Firebase.initializeApp();
      _ready = true;
      FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _opened(first);
    } catch (_) {}
  }

  void _opened(RemoteMessage m) =>
      onOpen?.call('${m.data['id'] ?? ''}', '${m.data['url'] ?? ''}');

  @override
  Future<void> sync(Subscription s) async {
    if (!_ready) return;
    final want = topicsFor(s);
    final have = (_prefs.getStringList(_key) ?? const <String>[]).toSet();
    try {
      final m = FirebaseMessaging.instance;
      for (final t in have.difference(want)) {
        await m.unsubscribeFromTopic(t);
      }
      for (final t in want.difference(have)) {
        await m.subscribeToTopic(t);
      }
      await _prefs.setStringList(_key, want.toList());
    } catch (_) {}
  }
}
