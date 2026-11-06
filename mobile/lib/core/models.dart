/// 주택형(면적 구간)별 공급 정보. 값이 없으면 null.
class HousingType {
  const HousingType({
    required this.type,
    this.exclusiveArea,
    this.supplyArea,
    this.priceMan,
    this.general,
    this.special,
    this.total,
  });

  final String type;
  final double? exclusiveArea; // 전용면적 ㎡
  final double? supplyArea; // 공급면적 ㎡
  final int? priceMan; // 최고 분양가, 만원
  final int? general;
  final int? special;
  final int? total;

  factory HousingType.fromJson(Map<String, dynamic> j) => HousingType(
        type: (j['type'] ?? '') as String,
        exclusiveArea: (j['exclusive_area'] as num?)?.toDouble(),
        supplyArea: (j['supply_area'] as num?)?.toDouble(),
        priceMan: (j['price_man'] as num?)?.toInt(),
        general: (j['general'] as num?)?.toInt(),
        special: (j['special'] as num?)?.toInt(),
        total: (j['total'] as num?)?.toInt(),
      );
}

/// 공고 위치. approx 가 true 면 주소가 아니라 이름으로 찾은 대략적인 위치다.
class GeoPoint {
  const GeoPoint(this.lat, this.lng, {this.approx = false});
  final double lat;
  final double lng;
  final bool approx;

  static GeoPoint? tryParse(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    return GeoPoint(lat.toDouble(), lng.toDouble(), approx: j['approx'] == true);
  }
}

/// 공고 한 건. notices.json 의 항목과 같은 모양이다.
/// id 는 '출처:원본ID' 형태의 문자열이라 수집을 다시 해도 바뀌지 않는다.
class Notice {
  Notice({
    required this.id,
    required this.source,
    required this.title,
    required this.tags,
    required this.sido,
    required this.url,
    this.announceDate,
    this.applyEnd,
    this.firstSeen,
    this.info = const {},
    this.types,
    this.geo,
    this.photo,
  });

  final String id;
  final String source;
  final String title;
  final List<String> tags;
  final String sido;
  final String url;
  final DateTime? announceDate;
  final DateTime? applyEnd;
  final DateTime? firstSeen; // 서버가 이 공고를 처음 본 시각
  final Map<String, dynamic> info; // 접수 시작·당첨자 발표·세대수 등 (청약홈 공고만 풍부)
  final List<HousingType>? types; // 주택형별 정보. 없으면 null
  final GeoPoint? geo; // 위치. 못 찾았으면 null
  final String? photo; // 분양 홈페이지의 대표 이미지 주소(https). 없으면 null

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        id: j['id'].toString(),
        source: j['source'] as String,
        title: j['title'] as String,
        tags: (j['tags'] as List? ?? const []).cast<String>(),
        sido: (j['sido'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        announceDate: _date(j['announce_date']),
        applyEnd: _date(j['apply_end']),
        firstSeen: _date(j['first_seen']),
        info: (j['info'] as Map?)?.cast<String, dynamic>() ?? const {},
        types: (j['types'] as List?)
            ?.map((e) => HousingType.fromJson(e as Map<String, dynamic>))
            .toList(),
        geo: GeoPoint.tryParse(j['geo']),
        photo: (j['photo'] is String && (j['photo'] as String).startsWith('https://')) ? j['photo'] as String : null,
      );

  bool get isResult => tags.contains('결과');

  /// 서버가 처음 본 지 24시간 안이면 새 공고.
  bool isNew([DateTime? now]) {
    final f = firstSeen;
    if (f == null) return false;
    final age = (now ?? DateTime.now()).difference(f);
    return !age.isNegative && age < const Duration(hours: 24);
  }

  /// 접수 마감까지 남은 일수. 마감일이 없거나 지났으면 null.
  int? daysLeft([DateTime? now]) {
    final end = applyEnd;
    if (end == null) return null;
    final n = now ?? DateTime.now();
    final d = DateTime(end.year, end.month, end.day)
        .difference(DateTime(n.year, n.month, n.day))
        .inDays;
    return d < 0 ? null : d;
  }

  String? str(String key) {
    final v = info[key];
    return (v == null || '$v'.isEmpty) ? null : '$v';
  }

  DateTime? infoDate(String key) => DateTime.tryParse(str(key) ?? '');
  int? infoInt(String key) => info[key] is num ? (info[key] as num).toInt() : null;
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

class Subscription {
  const Subscription({
    this.sido = const [],
    this.categories = const [],
    this.keywords = const [],
    this.excludeKeywords = const [],
    this.remindDays = const [3, 1],
  });

  /// 빈 목록은 "전체"를 뜻한다.
  final List<String> sido;
  final List<String> categories;
  final List<String> keywords;
  final List<String> excludeKeywords;
  final List<int> remindDays;

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        sido: (j['sido'] as List? ?? const []).cast<String>(),
        categories: (j['categories'] as List? ?? const []).cast<String>(),
        keywords: (j['keywords'] as List? ?? const []).cast<String>(),
        excludeKeywords: (j['exclude_keywords'] as List? ?? const []).cast<String>(),
        remindDays: (j['remind_days'] as List? ?? const [3, 1]).cast<int>(),
      );

  Map<String, dynamic> toJson() => {
        'sido': sido,
        'categories': categories,
        'keywords': keywords,
        'exclude_keywords': excludeKeywords,
        'remind_days': remindDays,
      };

  Subscription copyWith({
    List<String>? sido,
    List<String>? categories,
    List<String>? keywords,
    List<String>? excludeKeywords,
    List<int>? remindDays,
  }) =>
      Subscription(
        sido: sido ?? this.sido,
        categories: categories ?? this.categories,
        keywords: keywords ?? this.keywords,
        excludeKeywords: excludeKeywords ?? this.excludeKeywords,
        remindDays: remindDays ?? this.remindDays,
      );

  /// 서버 matching.py 와 같은 규칙: 빈 조건 = 전체, 결과성 공고는 제외.
  bool matches(Notice n) {
    if (n.isResult) return false;
    if (sido.isNotEmpty && !sido.contains(n.sido)) return false;
    if (categories.isNotEmpty && !n.tags.any(categories.contains)) return false;
    if (keywords.isNotEmpty && !keywords.any(n.title.contains)) return false;
    if (excludeKeywords.any(n.title.contains)) return false;
    return true;
  }
}

class NoticeFilter {
  const NoticeFilter({this.sido, this.category, this.query = '', this.mineOnly = false});
  final String? sido;
  final String? category;
  final String query;
  final bool mineOnly; // 내 관심 조건에 맞는 공고만

  NoticeFilter copyWith({
    String? sido,
    String? category,
    String? query,
    bool? mineOnly,
    bool clearSido = false,
    bool clearCategory = false,
  }) =>
      NoticeFilter(
        sido: clearSido ? null : (sido ?? this.sido),
        category: clearCategory ? null : (category ?? this.category),
        query: query ?? this.query,
        mineOnly: mineOnly ?? this.mineOnly,
      );

  /// 목록 화면용 필터. 결과성 공고(당첨자 발표 등)는 기본적으로 숨긴다.
  List<Notice> apply(List<Notice> all, [Subscription mine = const Subscription()]) {
    return all.where((n) {
      if (n.isResult) return false;
      if (sido != null && n.sido != sido) return false;
      if (category != null && !n.tags.contains(category)) return false;
      if (query.isNotEmpty && !n.title.contains(query)) return false;
      if (mineOnly && !mine.matches(n)) return false;
      return true;
    }).toList();
  }
}
