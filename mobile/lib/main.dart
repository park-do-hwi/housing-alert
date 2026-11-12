import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/models.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'core/user_store.dart';
import 'screens/calendar_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/detail_screen.dart';
import 'core/push.dart';
import 'screens/feed_screen.dart';
import 'screens/my_schedule_screen.dart';
import 'screens/news_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/web_screen.dart';
import 'widgets/ad_banner.dart';
import 'widgets/splash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  final prefs = await SharedPreferences.getInstance();
  final userStore = await UserStore.open();
  AdService.init(); // 기다리지 않는다: 광고 준비가 앱 시작을 늦추지 않게
  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        userStoreProvider.overrideWithValue(userStore),
      ],
      child: const HousingApp(),
    ),
  );
}

class HousingApp extends ConsumerStatefulWidget {
  const HousingApp({super.key});
  @override
  ConsumerState<HousingApp> createState() => _HousingAppState();
}

class _HousingAppState extends ConsumerState<HousingApp> {
  late final FcmPushService _push = FcmPushService(
    ref.read(prefsProvider),
    onOpen: _openFromPush,
  );

  /// 알림을 누르면 그 공고의 상세 화면으로. 목록에 없으면 원문 페이지를 연다.
  Future<void> _openFromPush(String id, String url) async {
    // 사용자가 건 목록 필터와 상관없이 전체 공고에서 찾는다.
    // 처음 켜질 때는 공고를 아직 못 불러왔을 수 있어 최대 6초까지 기다린다.
    Notice? find() {
      final data = ref.read(noticeDataProvider).value;
      if (data == null) return null;
      for (final n in data.items) {
        if (n.id == id) return n;
      }
      return null;
    }

    // 앱이 알림으로 막 켜졌다면 첫 화면(라우터)이 그려지기 전에 이동하면 빈 화면이 된다. 첫 프레임 뒤로 미룬다.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    for (var i = 0; i < 12 && ref.read(noticeDataProvider).value == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    var hit = find();
    print(
      'DBG hit=${hit?.title} dataNull=${ref.read(noticeDataProvider).value == null}',
    );
    if (hit == null) {
      // 저장된 목록이 옛것일 수 있다(방금 올라온 공고). 한 번 새로 받아 다시 찾는다.
      try {
        await ref.refresh(noticeDataProvider.future); // ignore: unused_result
      } catch (_) {}
      hit = find();
    }
    if (hit != null) {
      router.push('/notice', extra: hit);
      return;
    }
    if (url.startsWith('http')) router.push('/web', extra: url);
    // 공고도 원문 주소도 없으면 흰 화면 대신 목록을 그대로 둔다.
  }

  @override
  void initState() {
    super.initState();
    _push.init().then((_) => _push.sync(ref.read(subscriptionProvider)));
  }

  /// 첫 실행에서 알림 권한을 묻기 전에 무엇을 위한 알림인지 먼저 설명한다. 거절해도 앱은 그대로 쓸 수 있다.
  Future<void> _askPush(BuildContext context) async {
    // 푸시 초기화가 끝날 때까지 잠깐 기다린다.
    for (var i = 0; i < 10 && !await _push.needsAsk(); i++) {
      if (i == 9) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('새 공고 알림을 받을까요?'),
        content: const Text(
          '관심 지역·유형의 새 분양 공고와 접수 일정을 알림으로 알려드려요. '
          '알림을 받지 않아도 공고 목록·검색·지도는 그대로 쓸 수 있고, 설정에서 언제든 바꿀 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('알림 받기'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _push.requestPermission();
    } else {
      await _push.markAsked();
    }
  }

  late final GoRouter router = GoRouter(
    // 처음부터 공고를 보여준다. 관심 조건은 '알림 설정'에서 나중에 정한다.
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => HomeShell(onFirstFrame: _askPush),
      ),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/compare', builder: (_, _) => const CompareScreen()),
      GoRoute(
        path: '/notice',
        builder: (_, state) => state.extra is Notice
            ? DetailScreen(notice: state.extra! as Notice)
            : HomeShell(onFirstFrame: _askPush),
      ),
      GoRoute(
        path: '/web',
        builder: (_, state) => state.extra is String
            ? WebScreen(url: state.extra! as String, title: '공고 원문')
            : HomeShell(onFirstFrame: _askPush),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(subscriptionProvider, (_, next) => _push.sync(next));
    return MaterialApp.router(
      title: '청약레이더',
      routerConfig: router,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      // 전체 글자를 살짝 줄인다. 기기의 글자 크기 설정은 그대로 곱해진다.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * 0.92),
          ),
          child: SplashOverlay(
            dark: switch (ref.read(themeModeProvider)) {
              ThemeMode.dark => true,
              ThemeMode.light => false,
              ThemeMode.system => mq.platformBrightness == Brightness.dark,
            },
            child: child!,
          ),
        );
      },
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.onFirstFrame});
  final void Function(BuildContext context)? onFirstFrame;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFirstFrame?.call(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          FeedScreen(),
          CalendarScreen(),
          NewsScreen(),
          MyScheduleScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBanner(unitId: adUnitHome),
          _NavBar(index: index, onSelect: (i) => setState(() => index = i)),
        ],
      ),
    );
  }
}

/// 하단 메뉴: 선택하면 아이콘과 글자를 함께 감싸는 알약 모양으로 표시한다.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  static const items = [
    (Icons.home_work_outlined, Icons.home_work, '공고'),
    (Icons.calendar_month_outlined, Icons.calendar_month, '캘린더'),
    (Icons.newspaper_outlined, Icons.newspaper, '뉴스·영상'),
    (Icons.bookmark_border, Icons.bookmark, '내 일정'),
    (Icons.settings_outlined, Icons.settings, '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (final (i, it) in items.indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: it.$3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelect(i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: i == index
                              ? (dark
                                    ? const Color(0xFF2B4A3A)
                                    : const Color(0xFFDBEAFE))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              i == index ? it.$2 : it.$1,
                              size: 22,
                              color: i == index
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              it.$3,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 11,
                                height: 14 / 11,
                                fontWeight: i == index
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: i == index
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
