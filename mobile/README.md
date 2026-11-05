# 분양 알리미 (모바일 앱)

Flutter 앱. 공고는 `../server`의 수집기가 만든 정적 JSON 에서 읽는다 (상시 서버 없음).

## 화면
- 온보딩: 관심 지역·유형·키워드 선택 → 기기의 내 정보 파일에 저장
- 공고 피드: 유형 칩 + 지역 필터, 당겨서 새로고침, 마감 D-day 표시
- 공고 상세: 태그·일정·원문 링크(외부 브라우저) + 참고용 안내
- 캘린더: 접수 마감일 기준 월간 보기
- 공고 상세(확장): 청약홈 공고는 접수 시작·당첨자 발표·계약 시작·공급 세대·입주 예정·위치·시공사와 주택형별 최고 분양가·세대수 표를 보여준다 (주택형은 수집할 때 미리 받아 JSON 에 담긴다). LH·SH 공고는 목록에 있는 정보만 나온다.
- 비교: 상세의 "비교 담기"로 2~3개를 담고, 공고·내 일정 화면의 "비교하기" 버튼으로 나란히 본다
- 내 일정: 상세의 북마크로 저장한 공고를 접수 중/마감일 없음/마감됨으로 나눠 본다
- 알림 설정: 지역·유형·키워드·마감 알림(D-3/2/1/당일) 수정

## 데이터와 내 정보
- 공고: 서버가 만든 정적 `notices.json`(`--dart-define=DATA_BASE=...`)을 받아 기기에 캐시한다. 못 받으면 마지막으로 받은 것을 "오프라인" 안내와 함께 보여준다.
- 내 정보(관심 조건·저장한 공고·온보딩 여부·이후 자격 진단용 `profile`)는 앱 문서 폴더의 `housing_alert_user.json` 하나에만 저장한다. 서버로 보내지 않는다.
  설정 화면에서 파일로 내보내기/가져오기가 된다. 가져오면 현재 내용이 파일 내용으로 바뀌며, 이 앱이 만든 파일인지·버전이 맞는지 검사한 뒤 확인을 받는다.

## 실행
루트의 `../README.md` 에 수집부터 앱 실행까지 순서가 있다. 앱만:
```powershell
$env:Path = "D:\TaskCore\tools\flutter\bin;$env:Path"
$env:ANDROID_HOME = "D:\TaskCore\tools\android-sdk"
flutter run --dart-define=DATA_BASE=http://10.0.2.2:8000
flutter test
flutter build apk --debug
```

## 알려둘 것
- 푸시(FCM)는 아직 미연동. `lib/core/push.dart` 주석에 방향(주제 구독)이 있다.
- Android 는 개발용으로 `usesCleartextTraffic=true`. **출시 전에 HTTPS 로 바꾸고 이 설정을 제거**할 것.
- `android/gradle.properties`의 `kotlin.incremental=false`는 pub 캐시(C:)와 프로젝트(D:)의 드라이브가 달라 생기는 빌드 오류 회피용.
- iOS 폴더는 생성만 했고 빌드 확인은 하지 않았다(Mac 필요).
