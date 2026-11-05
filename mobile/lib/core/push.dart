/// 푸시 알림 연동 자리.
///
/// 아직 Firebase 프로젝트가 없어서 비어 있다. 연결할 때:
///  1. Firebase 콘솔에서 Android 앱(kr.taskcore.housing_alert) 등록 → google-services.json 을 android/app 에 둔다.
///  2. `flutter pub add firebase_core firebase_messaging`, `flutterfire configure`
///  3. 아래 [init] 에서 관심 조건(지역·유형)에 해당하는 FCM 주제(topic)를 구독한다.
///     (서버·기기 등록 없이, 수집기가 meta.json 의 new 목록을 주제로 발송한다.)
abstract class PushService {
  Future<void> init();
}

class NoopPushService implements PushService {
  @override
  Future<void> init() async {}
}
