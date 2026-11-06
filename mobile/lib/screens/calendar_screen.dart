import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../widgets/common.dart';

/// 공고 종류별 색. 캘린더 점과 범례에 같이 쓴다.
const _kinds = [
  ('분양', Color(0xFF1D4ED8)),
  ('무순위', Color(0xFFEA580C)),
  ('장기전세', Color(0xFF7C3AED)),
  ('임대', Color(0xFF059669)),
];

Color _kindColor(Notice n) {
  for (final k in const ['무순위', '장기전세', '임대', '분양']) {
    if (n.tags.contains(k)) return _kinds.firstWhere((e) => e.$1 == k).$2;
  }
  return const Color(0xFF64748B);
}

String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// 접수 마감일 기준 월간 캘린더. (지역별 접수 시점 확인용)
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime focused = DateTime.now();
  DateTime selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(calendarProvider(_monthKey(focused)));
    final days = data.value ?? const <String, List<Notice>>{};
    final todays = days[dayKey(selected)] ?? const <Notice>[];

    return Scaffold(
      appBar: AppBar(title: const Text('접수 마감 캘린더')),
      body: Column(children: [
        TableCalendar<Notice>(
          locale: 'ko_KR',
          firstDay: DateTime.utc(2024, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: focused,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          availableCalendarFormats: const {CalendarFormat.month: '월'},
          selectedDayPredicate: (d) => isSameDay(d, selected),
          eventLoader: (d) => days[dayKey(d)] ?? const [],
          onDaySelected: (s, f) => setState(() {
            selected = s;
            focused = f;
          }),
          onPageChanged: (f) => setState(() => focused = f),
          calendarBuilders: CalendarBuilders<Notice>(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              final colors = <Color>{for (final n in events) _kindColor(n)}.take(4).toList();
              return Positioned(
                bottom: 4,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final c in colors)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final k in _kinds) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: k.$2, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(k.$1, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
            ],
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: data.isLoading && !data.hasValue
              ? const Center(child: CircularProgressIndicator())
              : data.hasError && !data.hasValue
                  ? ErrorRetry(error: data.error!, onRetry: () => ref.invalidate(noticeDataProvider))
                  : todays.isEmpty
                      ? const Center(child: Text('이 날 마감되는 공고가 없어요'))
                      : ListView.separated(
                          itemCount: todays.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) => NoticeTile(
                            notice: todays[i],
                            onTap: () => context.push('/notice', extra: todays[i]),
                          ),
                        ),
        ),
      ]),
    );
  }
}
