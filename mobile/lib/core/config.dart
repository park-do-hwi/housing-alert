class AppConfig {
  /// notices.json 이 있는 주소(끝의 / 없이). 빌드 시 `--dart-define=DATA_BASE=https://...` 로 바꾼다.
  /// 개발 중에는 PC에서 `python -m http.server 8000 --directory public` 로 띄우고,
  /// Android 에뮬레이터는 10.0.2.2 로 접근한다.
  static const dataBase =
      String.fromEnvironment('DATA_BASE', defaultValue: 'http://10.0.2.2:8000');
}

const sidoList = [
  '서울', '경기', '인천', '부산', '대구', '광주', '대전', '울산', '세종',
  '강원', '충북', '충남', '전북', '전남', '경북', '경남', '제주',
];

/// 서버 classify.py 의 태그와 동일해야 한다.
const categoryList = ['분양', '무순위', '장기전세', '임대'];
