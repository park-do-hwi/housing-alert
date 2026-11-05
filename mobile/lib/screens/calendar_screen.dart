import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../widgets/common.dart';

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
