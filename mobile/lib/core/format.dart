import 'models.dart';

String _comma(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 만원 단위 금액 → '9억 3,820만', '1억', '5,000만'.
String fmtPriceMan(int? man) {
  if (man == null) return '-';
  final eok = man ~/ 10000;
  final rest = man % 10000;
  if (eok == 0) return '${_comma(rest)}만';
  return rest == 0 ? '$eok억' : '$eok억 ${_comma(rest)}만';
}

String fmtArea(double? a) =>
    a == null ? '-' : '${a.toStringAsFixed(a == a.roundToDouble() ? 0 : 2)}㎡';

/// '202808' → '2028.08'
String fmtYm(String? ym) =>
    (ym == null || ym.length != 6) ? '-' : '${ym.substring(0, 4)}.${ym.substring(4)}';

/// 전화번호 표기: '16887002' → '1688-7002', '0212345678' → '02-1234-5678'. 알 수 없는 형태는 그대로.
String fmtTel(String raw) {
  final s = raw.trim();
  if (!RegExp(r'^\d+$').hasMatch(s)) return s;
  if (s.length == 8) return '${s.substring(0, 4)}-${s.substring(4)}';
  if (s.startsWith('02') && (s.length == 9 || s.length == 10)) {
    final tail = s.substring(2);
    final cut = tail.length - 4;
    return '02-${tail.substring(0, cut)}-${tail.substring(cut)}';
  }
  if (s.length == 10 || s.length == 11) {
    final cut = s.length - 4;
    return '${s.substring(0, 3)}-${s.substring(3, cut)}-${s.substring(cut)}';
  }
  return s;
}

/// 출처 표시 이름: APPLYHOME → 청약홈.
String sourceLabel(String s) => s == 'APPLYHOME' ? '청약홈' : s;

/// 주택형 목록의 요약값. 비교 화면과 상세 화면에서 같이 쓴다.
class TypeSummary {
  TypeSummary(List<HousingType> types) {
    final prices = types.map((t) => t.priceMan).whereType<int>().toList()..sort();
    final areas = types.map((t) => t.exclusiveArea).whereType<double>().toList()..sort();
    minPrice = prices.isEmpty ? null : prices.first;
    maxPrice = prices.isEmpty ? null : prices.last;
    minArea = areas.isEmpty ? null : areas.first;
    maxArea = areas.isEmpty ? null : areas.last;
    final totals = types.map((t) => t.total).whereType<int>();
    totalSupply = totals.isEmpty ? null : totals.fold<int>(0, (a, b) => a + b);
    final sp = types.map((t) => t.special).whereType<int>();
    special = sp.isEmpty ? null : sp.fold<int>(0, (a, b) => a + b);
    count = types.length;
  }

  int? minPrice, maxPrice, totalSupply, special;
  double? minArea, maxArea;
  late final int count;

  String get priceRange => minPrice == null
      ? '-'
      : (minPrice == maxPrice ? fmtPriceMan(minPrice) : '${fmtPriceMan(minPrice)} ~ ${fmtPriceMan(maxPrice)}');

  String get areaRange => minArea == null
      ? '-'
      : (minArea == maxArea ? fmtArea(minArea) : '${fmtArea(minArea)} ~ ${fmtArea(maxArea)}');
}
