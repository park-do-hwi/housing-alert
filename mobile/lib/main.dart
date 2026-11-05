import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/models.dart';
import 'core/providers.dart';
import 'core/user_store.dart';
import 'screens/calendar_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/my_schedule_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  final prefs = await SharedPreferences.getInstance();
  final userStore = await UserStore.open();
  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      userStoreProvider.overrideWithValue(userStore),
    ],
    child: const HousingApp(),
  ));
}

class HousingApp extends ConsumerStatefulWidget {
  const HousingApp({super.key});
  @override
  ConsumerState<HousingApp> createState() => _HousingAppState();
}

class _HousingAppState extends ConsumerState<HousingApp> {
  late final GoRouter router = GoRouter(
    initialLocation: ref.read(userDataProvider).onboarded ? '/' : '/onboarding',
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
    return MaterialApp.router(
      title: '분양 알리미',
      routerConfig: router,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0), useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF1565C0), brightness: Brightness.dark, useMaterial3: true),
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
      body: IndexedStack(index: index, children: const [
        FeedScreen(),
        CalendarScreen(),
        MyScheduleScreen(),
        SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work), label: '공고'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '캘린더'),
          NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: '내 일정'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: '알림 설정'),
        ],
      ),
    );
  }
}
