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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  final prefs = await SharedPreferences.getInstance();
  final userStore = await UserStore.open();
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
  late final FcmPushService _push = FcmPushService(ref.read(prefsProvider));

  @override
  void initState() {
    super.initState();
    _push.init().then((_) => _push.sync(ref.read(subscriptionProvider)));
  }

  late final GoRouter router = GoRouter(
    // 처음부터 공고를 보여준다. 관심 조건은 '알림 설정'에서 나중에 정한다.
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeShell()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/compare', builder: (_, _) => const CompareScreen()),
      GoRoute(
        path: '/notice',
        builder: (_, state) => DetailScreen(notice: state.extra! as Notice),
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
          child: child!,
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
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

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
      bottomNavigationBar: _NavBar(
        index: index,
        onSelect: (i) => setState(() => index = i),
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
