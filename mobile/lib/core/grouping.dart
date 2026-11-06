import 'models.dart';

/// 목록에서 공고를 나누는 단계. 위에서부터 급한 순서다.
enum Phase {
  closingSoon('마감 임박'),
  open('접수 중'),
  upcoming('접수 예정'),
  undated('접수일 미확인'),
  closed('마감');

  const Phase(this.label);
  final String label;
}

/// 임박으로 보는 기준(남은 일수 이하).
const closingSoonDays = 3;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

Phase phaseOf(Notice n, DateTime now) {
  final today = _day(now);
  final start = n.infoDate('apply_start');
  final end = n.applyEnd;
  if (end != null && _day(end).isBefore(today)) return Phase.closed;
  if (start != null && _day(start).isAfter(today)) return Phase.upcoming;
  if (end != null) {
    return _day(end).difference(today).inDays <= closingSoonDays ? Phase.closingSoon : Phase.open;
  }
  return Phase.undated;
}

/// 공고를 단계별로 묶고, 각 단계 안에서 볼 순서대로 정렬한다. 빈 단계는 빼고 돌려준다.
List<(Phase, List<Notice>)> groupNotices(List<Notice> list, DateTime now) {
  final groups = {for (final p in Phase.values) p: <Notice>[]};
  for (final n in list) {
    groups[phaseOf(n, now)]!.add(n);
  }
  int byEnd(Notice a, Notice b) => a.applyEnd!.compareTo(b.applyEnd!);
  int byAnnounceDesc(Notice a, Notice b) =>
      (b.announceDate ?? DateTime(0)).compareTo(a.announceDate ?? DateTime(0));

  groups[Phase.closingSoon]!.sort(byEnd);
  groups[Phase.open]!.sort(byEnd);
  groups[Phase.upcoming]!.sort((a, b) {
    final c = a.infoDate('apply_start')!.compareTo(b.infoDate('apply_start')!);
    return c != 0 ? c : byAnnounceDesc(a, b);
  });
  groups[Phase.undated]!.sort(byAnnounceDesc);
  groups[Phase.closed]!.sort((a, b) => byEnd(b, a));

  return [
    for (final p in Phase.values)
      if (groups[p]!.isNotEmpty) (p, groups[p]!),
  ];
}

/// 홈 위쪽 숫자 탭. 누르면 그 묶음만 보여준다.
enum FeedTab {
  closingSoon('마감 임박'),
  open('접수 중'),
  upcoming('접수 예정'),
  rush('무순위'),
  closed('마감');

  const FeedTab(this.label);
  final String label;

  bool matches(Notice n, DateTime now) {
    final p = phaseOf(n, now);
    return switch (this) {
      FeedTab.closingSoon => p == Phase.closingSoon,
      FeedTab.open => p == Phase.open,
      FeedTab.upcoming => p == Phase.upcoming,
      FeedTab.rush => n.tags.contains('무순위') && p != Phase.closed,
      FeedTab.closed => p == Phase.closed,
    };
  }
}

/// 단계별 접수 한 줄(특별공급·1순위·2순위).
class StagePeriod {
  const StagePeriod(this.label, this.start, this.end);
  final String label;
  final DateTime start;
  final DateTime end;

  /// -1 지남, 0 진행 중(오늘 포함), 1 아직
  int stateAt(DateTime now) {
    final t = _day(now);
    if (_day(end).isBefore(t)) return -1;
    if (_day(start).isAfter(t)) return 1;
    return 0;
  }
}

/// 수집된 단계별 접수일. 하나도 없으면 빈 목록(그땐 접수 기간 한 줄을 쓴다).
List<StagePeriod> stagePeriods(Notice n) {
  final out = <StagePeriod>[];
  for (final (label, k) in const [('특별공급', 'special'), ('1순위', 'rank1'), ('2순위', 'rank2')]) {
    final s = n.infoDate('${k}_start');
    final e = n.infoDate('${k}_end') ?? s;
    if (s != null && e != null) out.add(StagePeriod(label, s, e));
  }
  return out;
}

/// 카드 오른쪽 위 배지 문구: 'D-3', '오늘 마감', '5일 후 접수', '마감'. 알 수 없으면 null.
String? badgeLabel(Notice n, DateTime now) {
  final today = _day(now);
  switch (phaseOf(n, now)) {
    case Phase.closingSoon:
    case Phase.open:
      final d = _day(n.applyEnd!).difference(today).inDays;
      return d == 0 ? '오늘 마감' : 'D-$d';
    case Phase.upcoming:
      final d = _day(n.infoDate('apply_start')!).difference(today).inDays;
      return d == 1 ? '내일 접수' : '$d일 후 접수';
    case Phase.closed:
      return '마감';
    case Phase.undated:
      return null;
  }
}
