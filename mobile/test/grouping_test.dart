import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:housing_alert/core/format.dart';
import 'package:housing_alert/core/grouping.dart';
import 'package:housing_alert/core/models.dart';
import 'package:housing_alert/widgets/common.dart';

Notice n(String id, {String? start, String? end, String? ann, Map<String, dynamic> info = const {}}) =>
    Notice(
      id: id,
      source: 'LH',
      title: '공고 $id',
      tags: const ['분양'],
      sido: '서울',
      url: '',
      announceDate: ann == null ? null : DateTime.parse(ann),
      applyEnd: end == null ? null : DateTime.parse(end),
      info: {'apply_start': ?start, ...info},
    );

void main() {
  tabAndStageTests();
  final now = DateTime(2026, 11, 5, 14, 0);

  test('단계 판정: 마감 임박·접수 중·예정·미확인·마감', () {
    expect(phaseOf(n('a', end: '2026-11-05'), now), Phase.closingSoon); // 오늘 마감
    expect(phaseOf(n('b', end: '2026-11-08'), now), Phase.closingSoon); // 3일 남음
    expect(phaseOf(n('c', end: '2026-11-09'), now), Phase.open); // 4일 남음
    expect(phaseOf(n('d', start: '2026-11-04', end: '2026-11-20'), now), Phase.open);
    expect(phaseOf(n('e', start: '2026-11-09', end: '2026-11-12'), now), Phase.upcoming);
    expect(phaseOf(n('f', ann: '2026-11-01'), now), Phase.undated);
    expect(phaseOf(n('g', end: '2026-11-04'), now), Phase.closed);
  });

  test('단계별 묶음과 정렬, 빈 단계는 생략', () {
    final g = groupNotices([
      n('late', end: '2026-12-01'),
      n('soon2', end: '2026-11-07'),
      n('soon1', end: '2026-11-06'),
      n('up2', start: '2026-11-20', end: '2026-11-25'),
      n('up1', start: '2026-11-10', end: '2026-11-12'),
      n('none', ann: '2026-11-01'),
    ], now);
    expect(g.map((e) => e.$1).toList(),
        [Phase.closingSoon, Phase.open, Phase.upcoming, Phase.undated]);
    expect(g[0].$2.map((e) => e.id), ['soon1', 'soon2']);
    expect(g[2].$2.map((e) => e.id), ['up1', 'up2']);
  });

  test('배지 문구', () {
    expect(badgeLabel(n('a', end: '2026-11-05'), now), '오늘 마감');
    expect(badgeLabel(n('b', end: '2026-11-08'), now), 'D-3');
    expect(badgeLabel(n('c', start: '2026-11-06', end: '2026-11-09'), now), '내일 접수');
    expect(badgeLabel(n('d', start: '2026-11-15', end: '2026-11-18'), now), '10일 후 접수');
    expect(badgeLabel(n('e', ann: '2026-11-01'), now), isNull);
  });

  test('짧은 금액 표기', () {
    expect(fmtPriceShort(74520), '7.5억');
    expect(fmtPriceShort(93780), '9.4억');
    expect(fmtPriceShort(60000), '6억');
    expect(fmtPriceShort(5000), '5,000만');
    expect(fmtPriceShort(null), '-');
  });

  test('접수 기간 문구', () {
    expect(periodText(n('a', start: '2026-11-05', end: '2026-11-09')), '접수 11.5 ~ 11.9');
    expect(periodText(n('b', start: '2026-11-09', end: '2026-11-09')), '접수 11.9');
    expect(periodText(n('c', end: '2026-11-09')), '마감 11.9');
    expect(periodText(n('d')), isNull);
  });

  testWidgets('카드에 핵심 수치가 보인다', (tester) async {
    final notice = n('x',
        start: '2026-11-05', end: '2026-11-07', info: {'total_households': 279});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NoticeTile(notice: notice, now: now, onTap: () {}))));
    expect(find.text('D-2'), findsOneWidget);
    expect(find.textContaining('접수 11.5 ~ 11.7'), findsOneWidget);
    expect(find.textContaining('279세대'), findsOneWidget);
  });
}

void tabAndStageTests() {
  final now = DateTime(2026, 11, 5, 14, 0);

  test('숫자 탭: 단계와 무순위 구분', () {
    final rush = Notice(
        id: 'r', source: 'APPLYHOME', title: 'r', tags: const ['무순위'], sido: '서울', url: '',
        applyEnd: DateTime(2026, 11, 20), info: const {});
    expect(FeedTab.rush.matches(rush, now), isTrue);
    expect(FeedTab.open.matches(rush, now), isTrue);
    expect(FeedTab.closed.matches(n('c', end: '2026-11-01'), now), isTrue);
    expect(FeedTab.rush.matches(n('x', end: '2026-11-20'), now), isFalse);
  });

  test('단계별 접수: 있는 것만, 진행 상태 판정', () {
    final a = n('s', end: '2026-11-17', info: {
      'special_start': '2026-11-02', 'special_end': '2026-11-04', 'rank1_start': '2026-11-05',
      'rank1_end': '2026-11-05', 'rank2_start': '2026-11-17', 'rank2_end': '2026-11-17',
    });
    final st = stagePeriods(a);
    expect(st.map((e) => e.label), ['특별공급', '1순위', '2순위']);
    expect(st.map((e) => e.stateAt(now)), [-1, 0, 1]);
    expect(stagePeriods(n('none', end: '2026-11-17')), isEmpty);
  });

  test('NEW 는 처음 본 지 24시간 안', () {
    Notice seen(String t) => Notice(
        id: 'n', source: 'LH', title: 't', tags: const [], sido: '', url: '', firstSeen: DateTime.parse(t));
    expect(seen('2026-11-05T01:00:00').isNew(now), isTrue);
    expect(seen('2026-11-04T13:00:00').isNew(now), isFalse);
    expect(n('x').isNew(now), isFalse);
  });
}
