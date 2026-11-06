import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:housing_alert/core/file_io.dart';
import 'package:housing_alert/core/format.dart';
import 'package:housing_alert/core/models.dart';
import 'package:housing_alert/core/providers.dart';
import 'package:housing_alert/core/repository.dart';
import 'package:housing_alert/core/user_store.dart';
import 'package:housing_alert/screens/compare_screen.dart';
import 'package:housing_alert/screens/detail_screen.dart';
import 'package:housing_alert/screens/feed_screen.dart';
import 'package:housing_alert/screens/my_schedule_screen.dart';
import 'package:housing_alert/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _json(String id, String title,
        {String? end,
        String sido = '서울',
        List<String> tags = const ['무순위', '분양'],
        Map<String, dynamic> info = const {},
        List<Map<String, dynamic>>? types}) =>
    {
      'id': id,
      'source': 'LH',
      'title': title,
      'tags': tags,
      'sido': sido,
      'announce_date': '2026-11-03',
      'apply_end': end,
      'url': 'https://example.com/$id',
      'info': info,
      'types': types,
    };

Notice _n(String id, String title, {String? end, String sido = '서울', List<String> tags = const ['무순위']}) =>
    Notice.fromJson(_json(id, title, end: end, sido: sido, tags: tags));

String _future() {
  final d = DateTime.now().add(const Duration(days: 2));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class FakeFileIo implements FileIo {
  FakeFileIo({this.pickBytes});
  Uint8List? pickBytes;
  String? savedName;
  Uint8List? savedBytes;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    savedName = fileName;
    savedBytes = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => pickBytes;
}

late SharedPreferences _fakePrefs;

List<Override> _overrides(
        {List<Notice>? items, UserStore? store, FileIo? io, bool stale = false, SharedPreferences? prefs}) =>
    [
      prefsProvider.overrideWithValue(prefs ?? _fakePrefs),
      userStoreProvider.overrideWithValue(store ?? UserStore.inMemory()),
      noticeDataProvider.overrideWith(
          (ref) async => NoticeData(items: items ?? const [], generatedAt: DateTime(2026, 11, 5, 18), stale: stale)),
      if (io != null) fileIoProvider.overrideWithValue(io),
    ];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _fakePrefs = await SharedPreferences.getInstance();
  });

  // ---------- 모델 ----------
  test('Notice.daysLeft: 마감 전/당일/지남/없음', () {
    final now = DateTime(2026, 11, 5, 15);
    expect(_n('1', 't', end: '2026-11-08').daysLeft(now), 3);
    expect(_n('1', 't', end: '2026-11-05').daysLeft(now), 0);
    expect(_n('1', 't', end: '2026-11-04').daysLeft(now), isNull);
    expect(_n('1', 't').daysLeft(now), isNull);
  });

  test('NoticeFilter: 지역·유형·검색어·내 조건, 결과성 공고는 숨김', () {
    final all = [
      _n('1', '서울 장기전세', tags: ['장기전세']),
      _n('2', '경기 무순위', sido: '경기'),
      _n('3', '서울 당첨자 발표', tags: ['장기전세', '결과']),
    ];
    expect(const NoticeFilter().apply(all).map((e) => e.id), ['1', '2']);
    expect(const NoticeFilter(sido: '경기').apply(all).map((e) => e.id), ['2']);
    expect(const NoticeFilter(category: '장기전세').apply(all).map((e) => e.id), ['1']);
    expect(const NoticeFilter(query: '무순위').apply(all).map((e) => e.id), ['2']);
    const mine = Subscription(sido: ['서울'], categories: ['장기전세']);
    expect(const NoticeFilter(mineOnly: true).apply(all, mine).map((e) => e.id), ['1']);
  });

  test('Subscription.matches: 빈 조건은 전체, 제외 키워드 우선', () {
    final n = _n('1', '서울 신혼 오피스텔', tags: ['분양']);
    expect(const Subscription().matches(n), isTrue);
    expect(const Subscription(keywords: ['신혼']).matches(n), isTrue);
    expect(const Subscription(keywords: ['신혼'], excludeKeywords: ['오피스텔']).matches(n), isFalse);
    expect(const Subscription(sido: ['부산']).matches(n), isFalse);
  });

  test('금액·면적·연월 표기와 주택형 요약', () {
    expect(fmtPriceMan(93820), '9억 3,820만');
    expect(fmtPriceMan(100000), '10억');
    expect(fmtPriceMan(5000), '5,000만');
    expect(fmtArea(84.0), '84㎡');
    expect(fmtYm('202808'), '2028.08');
    final s = TypeSummary(const [
      HousingType(type: 'A', exclusiveArea: 63.14, priceMan: 93820, general: 5, special: 0, total: 5),
      HousingType(type: 'B', exclusiveArea: 84.09, priceMan: 132100, general: 43, special: 2, total: 45),
    ]);
    expect(s.priceRange, '9억 3,820만 ~ 13억 2,100만');
    expect(s.totalSupply, 50);
  });

  test('비교 담기는 최대 3개이고 같은 공고를 다시 누르면 빠진다', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(compareSelectionProvider.notifier);
    expect(n.toggle(_n('1', 'a')), isTrue);
    expect(n.toggle(_n('2', 'b')), isTrue);
    expect(n.toggle(_n('3', 'c')), isTrue);
    expect(n.toggle(_n('4', 'd')), isFalse);
    expect(n.toggle(_n('2', 'b')), isTrue);
    expect(c.read(compareSelectionProvider).map((e) => e.id), ['1', '3']);
  });

  // ---------- 정적 JSON 저장소 ----------
  String body(List<Map<String, dynamic>> items) =>
      jsonEncode({'generated_at': '2026-11-05T09:00:00+00:00', 'items': items});

  test('NoticeRepository: 성공하면 기기에 저장하고 stale 이 아니다', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Uri? seen;
    final repo = NoticeRepository('http://x/', prefs, MockClient((req) async {
      seen = req.url;
      return http.Response.bytes(utf8.encode(body([_json('LH:1', '래미안 무순위')])), 200);
    }));
    final d = await repo.load();
    expect(seen.toString(), 'http://x/notices.json');   // 끝의 / 중복 없음
    expect(d.items.single.title, '래미안 무순위');       // 한글 유지
    expect(d.stale, isFalse);
    expect(prefs.getString(NoticeRepository.cacheKey), isNotNull);
  });

  test('NoticeRepository: 네트워크 실패 시 저장본을 stale 로 돌려준다', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NoticeRepository.cacheKey, body([_json('LH:1', '저장본')]));
    for (final client in [
      MockClient((_) async => throw const SocketException('offline')),
      MockClient((_) async => http.Response('boom', 503)),
      MockClient((_) async => http.Response('<html>not json</html>', 200)),
    ]) {
      final d = await NoticeRepository('http://x', prefs, client).load();
      expect(d.stale, isTrue);
      expect(d.items.single.title, '저장본');
    }
  });

  test('NoticeRepository: 저장본도 없으면 오류, 깨진 응답은 저장본을 덮어쓰지 않는다', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final off = MockClient((_) async => throw const SocketException('offline'));
    await expectLater(NoticeRepository('http://x', prefs, off).load(), throwsA(isA<NoticeLoadException>()));
    await prefs.setString(NoticeRepository.cacheKey, body([_json('LH:1', '좋은 저장본')]));
    await NoticeRepository('http://x', prefs, MockClient((_) async => http.Response('garbage', 200))).load();
    expect(prefs.getString(NoticeRepository.cacheKey), contains('좋은 저장본'));
  });

  // ---------- 실제 수집 결과와의 호환 ----------
  test('서버가 만든 실제 notices.json 을 모델이 그대로 읽는다', () {
    final f = File('../server/public/notices.json');
    if (!f.existsSync()) {
      markTestSkipped('../server/public/notices.json 없음 (python -m app.export 로 생성)');
      return;
    }
    final d = NoticeRepository.parse(f.readAsStringSync());
    expect(d.items.length, greaterThan(50));
    expect(d.generatedAt, isNotNull);
    expect(d.items.every((n) => n.id.contains(':') && n.title.isNotEmpty), isTrue);
    expect(d.items.map((n) => n.source).toSet(), containsAll(['LH', 'SH', 'APPLYHOME']));
    final withTypes = d.items.where((n) => n.types != null && n.types!.isNotEmpty).toList();
    expect(withTypes, isNotEmpty);
    expect(withTypes.first.types!.first.priceMan, isNotNull);
    expect(const NoticeFilter().apply(d.items), isNotEmpty);
  });

  // ---------- 내 정보 파일 ----------
  test('UserStore: 파일로 저장했다가 다시 열면 그대로', () async {
    final dir = await Directory.systemTemp.createTemp('ua_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await UserStore.open(dir: dir);
    expect(store.data.onboarded, isFalse);
    await store.save(const UserData(
      subscription: Subscription(sido: ['서울'], categories: ['무순위'], keywords: ['신혼']),
      favorites: ['LH:1', 'SH:2'],
      onboarded: true,
      profile: {'homeless_years': 5},
    ));
    expect(await File('${dir.path}/${UserStore.fileName}').exists(), isTrue);
    expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    final again = await UserStore.open(dir: dir);
    expect(again.data.subscription.keywords, ['신혼']);
    expect(again.data.favorites, ['LH:1', 'SH:2']);
    expect(again.data.profile['homeless_years'], 5);
    expect(again.data.onboarded, isTrue);
  });

  test('UserStore: 깨진 파일은 .broken 으로 보관하고 빈 상태로 시작', () async {
    final dir = await Directory.systemTemp.createTemp('ua_');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/${UserStore.fileName}').writeAsString('{ not json');
    final store = await UserStore.open(dir: dir);
    expect(store.data.favorites, isEmpty);
    expect(await File('${dir.path}/${UserStore.fileName}.broken').exists(), isTrue);
  });

  test('UserStore.decode: 다른 파일·새 버전·잘못된 JSON 거절', () {
    expect(() => UserStore.decode('not json'), throwsA(isA<UserFileException>()));
    expect(() => UserStore.decode('{"app":"other","version":1}'), throwsA(isA<UserFileException>()));
    expect(() => UserStore.decode('{"app":"housing_alert","version":99}'), throwsA(isA<UserFileException>()));
    expect(() => UserStore.decodeBytes([0xff, 0xfe, 0xfd]), throwsA(isA<UserFileException>()));
    final ok = UserStore.decode(UserStore.encode(const UserData(favorites: ['a'])));
    expect(ok.favorites, ['a']);
  });

  // ---------- 화면 ----------
  testWidgets('피드: 목록·D-day·갱신 시각, 결과성 공고는 숨김', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(items: [
        _n('1', '래미안 OO 무순위', end: _future()),
        _n('2', '다른 단지'),
        _n('3', '당첨자 발표 공고', tags: ['장기전세', '결과']),
      ]),
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('래미안 OO 무순위'), findsOneWidget);
    expect(find.text('D-2'), findsOneWidget);
    expect(find.text('다른 단지'), findsOneWidget);
    expect(find.text('당첨자 발표 공고'), findsNothing);
    expect(find.textContaining('11.05 18:00 기준'), findsOneWidget);
  });

  testWidgets('피드: 오프라인이면 안내 문구, 데이터 오류면 다시 시도', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(items: [_n('1', '저장본 공고')], stale: true),
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('오프라인'), findsOneWidget);
    expect(find.text('저장본 공고'), findsOneWidget);

    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),  // 같은 위치의 ProviderScope 를 재사용하지 않도록
      overrides: [
        userStoreProvider.overrideWithValue(UserStore.inMemory()),
        noticeDataProvider.overrideWith((ref) async => throw NoticeLoadException('공고 데이터를 불러오지 못했어요')),
      ],
      child: const MaterialApp(home: FeedScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('상세: 북마크가 저장되고 해제되며 내 정보에 반영된다', (tester) async {
    final store = UserStore.inMemory();
    final n = _n('LH:1', '저장할 단지', end: '2099-01-01');
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(items: [n], store: store),
      child: MaterialApp(home: DetailScreen(notice: n)),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(store.data.favorites, ['LH:1']);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(store.data.favorites, isEmpty);
  });

  testWidgets('상세: 청약홈 일정·세대수와 주택형 표를 보여준다', (tester) async {
    final n = Notice.fromJson(_json('APPLYHOME:1', '센텀 단지', end: '2099-01-01', info: {
      'apply_start': '2026-11-09', 'winner_date': '2026-11-12',
      'total_households': 53, 'move_in_ym': '202901', 'address': '부산 수영구',
    }, types: [
      {'type': '084.0948', 'exclusive_area': 84.09, 'supply_area': null,
       'price_man': 132100, 'general': 43, 'special': 0, 'total': 43},
    ]));
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(items: [n]),
      child: MaterialApp(home: DetailScreen(notice: n)),
    ));
    await tester.pumpAndSettle();
    // 핵심 3칸: 공급 세대·분양가 범위가 맨 위에 보인다
    expect(find.text('한눈에 보기'), findsOneWidget);
    expect(find.textContaining('총 53세대'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('13억 2,100만'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('13억 2,100만'), findsOneWidget); // 주택형 표
    expect(find.text('주택형별 공급'), findsOneWidget);
    expect(find.text('청약 일정'), findsOneWidget);
    expect(find.text('당첨자 발표'), findsOneWidget);
    // 부가 정보는 기본 접힘 → 펼치면 입주 예정이 보인다
    expect(find.text('2029.01'), findsNothing);
    await tester.scrollUntilVisible(find.text('부가 정보'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('부가 정보'));
    await tester.pumpAndSettle();
    expect(find.text('2029.01'), findsOneWidget);
    expect(find.text('부산 수영구'), findsOneWidget);
  });

  testWidgets('상세: 주택형이 없는 LH·SH 공고도 열린다', (tester) async {
    final n = _n('LH:2', 'LH 공고', end: '2099-01-01');
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(items: [n]),
      child: MaterialApp(home: DetailScreen(notice: n)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('주택형별 공급'), findsNothing);
    expect(find.text('원문 공고 보기'), findsOneWidget);
  });

  testWidgets('내 일정: 저장한 공고를 접수 중 구간으로, 목록에서 빠진 공고는 건너뜀', (tester) async {
    final store = UserStore.inMemory(const UserData(favorites: ['LH:1', 'LH:gone']));
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(items: [_n('LH:1', '접수중 단지', end: _future())], store: store),
      child: const MaterialApp(home: MyScheduleScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('접수중 단지'), findsOneWidget);
    expect(find.textContaining('접수 중'), findsOneWidget);
  });

  testWidgets('비교 화면: 두 공고를 나란히 보여준다', (tester) async {
    final items = [
      Notice.fromJson(_json('1', '단지 A', info: {'total_households': 53}, types: [
        {'type': 'a', 'exclusive_area': 84.0, 'price_man': 90000, 'general': 5, 'special': 0, 'total': 5}
      ])),
      Notice.fromJson(_json('2', '단지 B', info: {'total_households': 10})),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CompareTable(items: items))));
    expect(find.text('단지 A'), findsOneWidget);
    expect(find.text('9억'), findsOneWidget);
    expect(find.text('53'), findsOneWidget);
    expect(find.text('-'), findsWidgets);
  });

  testWidgets('설정: 파일로 내보내면 내 정보가 담긴 JSON 이 저장된다', (tester) async {
    final io = FakeFileIo();
    final store = UserStore.inMemory(const UserData(
        subscription: Subscription(sido: ['서울']), favorites: ['LH:1'], onboarded: true));
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(store: store, io: io),
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('파일로 내보내기'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('파일로 내보내기'));
    await tester.pumpAndSettle();
    expect(io.savedName, UserStore.fileName);
    final saved = UserStore.decodeBytes(io.savedBytes!);
    expect(saved.favorites, ['LH:1']);
    expect(saved.subscription.sido, ['서울']);
    expect(find.text('파일로 저장했어요'), findsOneWidget);
  });

  testWidgets('설정: 파일에서 가져오기는 확인 후 내용을 바꾸고, 엉뚱한 파일은 거절', (tester) async {
    final store = UserStore.inMemory(const UserData(favorites: ['old'], onboarded: true));
    final incoming = Uint8List.fromList(utf8.encode(UserStore.encode(
        const UserData(subscription: Subscription(sido: ['부산']), favorites: ['LH:7', 'SH:8']))));
    final io = FakeFileIo(pickBytes: incoming);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(store: store, io: io),
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('파일에서 가져오기'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('파일에서 가져오기'));
    await tester.pumpAndSettle();
    expect(find.text('파일에서 가져올까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(store.data.favorites, ['old']);                 // 취소하면 그대로

    await tester.tap(find.text('파일에서 가져오기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가져오기').last);
    await tester.pumpAndSettle();
    expect(store.data.favorites, ['LH:7', 'SH:8']);
    expect(store.data.subscription.sido, ['부산']);

    io.pickBytes = Uint8List.fromList(utf8.encode('{"hello":1}'));
    await tester.tap(find.text('파일에서 가져오기'));
    await tester.pumpAndSettle();
    expect(find.text('이 앱에서 내보낸 파일이 아니에요'), findsOneWidget);
    expect(store.data.favorites, ['LH:7', 'SH:8']);        // 거절되면 변하지 않음
  });
}


