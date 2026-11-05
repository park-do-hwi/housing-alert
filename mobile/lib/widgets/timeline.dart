import 'package:flutter/material.dart';

import '../core/grouping.dart' show Phase;
import '../core/theme.dart';
import 'common.dart' show fmtMd;

/// 일정 한 칸: 단계 이름과 날짜.
class TimelineEvent {
  const TimelineEvent(this.label, this.date);
  final String label;
  final DateTime date;
}

enum StepState { done, today, upcoming }

StepState stepState(DateTime date, DateTime now) {
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(now.year, now.month, now.day);
  if (d.isBefore(t)) return StepState.done;
  return d == t ? StepState.today : StepState.upcoming;
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
String fmtMdW(DateTime d) => '${fmtMd(d)}(${_weekdays[d.weekday - 1]})';

/// 세로 일정 타임라인. 실제로 있는 날짜만 그리고(없는 단계는 만들지 않음), 날짜 순으로 정렬한다.
/// 상태는 글자(완료/오늘/예정)와 아이콘으로 함께 표시해 색에만 의존하지 않는다.
class ScheduleTimeline extends StatelessWidget {
  const ScheduleTimeline({super.key, required this.events, this.now});
  final List<TimelineEvent> events;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final sorted = [...events]..sort((a, b) => a.date.compareTo(b.date));
    final colors = context.appColors;
    final theme = Theme.of(context);

    return Column(children: [
      for (var i = 0; i < sorted.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 28,
              child: Column(children: [
                Container(width: 2, height: 6, color: i == 0 ? Colors.transparent : theme.colorScheme.outlineVariant),
                _dot(stepState(sorted[i].date, at), colors, theme),
                Expanded(
                  child: Container(
                      width: 2, color: i == sorted.length - 1 ? Colors.transparent : theme.colorScheme.outlineVariant),
                ),
              ]),
            ),
            Expanded(child: _row(sorted[i], stepState(sorted[i].date, at), colors, theme)),
          ]),
        ),
    ]);
  }

  Widget _dot(StepState s, AppColors colors, ThemeData theme) {
    switch (s) {
      case StepState.done:
        return Icon(Icons.check_circle, size: 20, color: theme.colorScheme.onSurfaceVariant);
      case StepState.today:
        return Icon(Icons.radio_button_checked, size: 20, color: colors.phaseTone(Phase.open).fg);
      case StepState.upcoming:
        return Icon(Icons.radio_button_unchecked, size: 20, color: theme.colorScheme.primary);
    }
  }

  Widget _row(TimelineEvent e, StepState s, AppColors colors, ThemeData theme) {
    final state = switch (s) { StepState.done => '완료', StepState.today => '오늘', StepState.upcoming => '예정' };
    final fg = s == StepState.today ? colors.phaseTone(Phase.open).fg : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(e.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: s == StepState.upcoming || s == StepState.today ? FontWeight.w700 : FontWeight.w400)),
        ),
        Text(fmtMdW(e.date), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(state,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w600, color: fg)),
        ),
      ]),
    );
  }
}
