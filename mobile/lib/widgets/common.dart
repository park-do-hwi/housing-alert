import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/grouping.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';

class TagChip extends StatelessWidget {
  const TagChip(this.tag, {super.key});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final tone = context.appColors.tagTone(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(Gap.tagRadius),
      ),
      child: Text(tag, style: TextStyle(fontSize: 12, height: 18 / 12, color: tone.fg, fontWeight: FontWeight.w600)),
    );
  }
}

/// 아파트 이미지 자리. 공고 데이터에 사진이 없어서, 대표 유형 색과 아이콘으로 단지를 구분해 보여준다.
class ApartmentThumb extends StatelessWidget {
  const ApartmentThumb({super.key, required this.notice, this.size = 64});
  final Notice notice;
  final double size;

  static IconData iconFor(List<String> tags) {
    if (tags.contains('무순위')) return Icons.bolt_rounded;
    if (tags.contains('장기전세')) return Icons.home_work_rounded;
    if (tags.contains('임대')) return Icons.holiday_village_rounded;
    return Icons.apartment_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final main = ['무순위', '장기전세', '분양', '임대'].firstWhere(notice.tags.contains, orElse: () => '');
    final tone = context.appColors.tagTone(main);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Gap.chipRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone.bg, tone.fg.withValues(alpha: 0.22)],
        ),
      ),
      child: Icon(iconFor(notice.tags), size: size * 0.5, color: tone.fg),
    );
  }
}

/// 'D-3', '오늘 마감' 등. 마감일이 없으면 null.
String? ddayLabel(Notice n) {
  final d = n.daysLeft();
  if (d == null) return null;
  return d == 0 ? '오늘 마감' : 'D-$d';
}

String fmtDate(DateTime? d) => d == null
    ? '-'
    : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            Text('불러오지 못했어요\n$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
          ]),
        ),
      );
}

/// '11.9' 형태의 짧은 날짜.
String fmtMd(DateTime d) => '${d.month}.${d.day}';

/// 접수 기간 한 줄: '접수 11.5 ~ 11.9', '접수 11.9', '마감 11.9', 없으면 null.
String? periodText(Notice n) {
  final s = n.infoDate('apply_start');
  final e = n.applyEnd;
  if (s != null && e != null) {
    final same = s.year == e.year && s.month == e.month && s.day == e.day;
    return same ? '접수 ${fmtMd(e)}' : '접수 ${fmtMd(s)} ~ ${fmtMd(e)}';
  }
  if (s != null) return '접수 ${fmtMd(s)}~';
  if (e != null) return '마감 ${fmtMd(e)}';
  return null;
}

IconData phaseIcon(Phase p) => switch (p) {
      Phase.closingSoon => Icons.local_fire_department_rounded,
      Phase.open => Icons.play_circle_outline_rounded,
      Phase.upcoming => Icons.event_available_rounded,
      Phase.undated => Icons.help_outline_rounded,
      Phase.closed => Icons.check_circle_outline_rounded,
    };

/// 목록 한 건: 왼쪽 단지 이미지, 제목 + 상태 배지, 지역·출처, 핵심 수치(접수 기간·세대수·분양가), 태그.
class NoticeTile extends StatelessWidget {
  const NoticeTile({super.key, required this.notice, required this.onTap, this.now});
  final Notice notice;
  final VoidCallback onTap;
  final DateTime? now; // 테스트용. 기본은 현재 시각

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final phase = phaseOf(notice, at);
    final badge = badgeLabel(notice, at);
    final tone = context.appColors.phaseTone(phase);
    final theme = Theme.of(context);
    final grey = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final households = notice.infoInt('total_households');
    final types = notice.types;
    final price = (types == null || types.isEmpty) ? null : TypeSummary(types).priceRange;
    final facts = <String>[
      ?periodText(notice),
      if (households != null) '$households세대',
      if (price != null && price != '-') price,
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ApartmentThumb(notice: notice),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(bottom: Gap.xs),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(Gap.tagRadius)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(phaseIcon(phase), size: 14, color: tone.fg),
                    const SizedBox(width: 4),
                    Text(badge,
                        style: TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w700, color: tone.fg)),
                  ]),
                ),
              Text(notice.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${notice.sido.isEmpty ? '' : '${notice.sido} · '}${sourceLabel(notice.source)}',
                  style: grey),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Wrap(spacing: 12, runSpacing: 2, children: [
                  for (final f in facts)
                    Text(f,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
                ]),
              ],
              const SizedBox(height: Gap.sm),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final t in notice.tags.where((t) => t != '정정' && t != '기타')) TagChip(t),
                if (notice.tags.contains('정정')) const TagChip('정정'),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 목록의 단계 제목줄: '마감 임박 3'. [collapsible]이면 눌러서 접고 펼친다(마감 단계).
class PhaseHeader extends StatelessWidget {
  const PhaseHeader({
    super.key,
    required this.phase,
    required this.count,
    this.collapsible = false,
    this.collapsed = false,
    this.onToggle,
  });
  final Phase phase;
  final int count;
  final bool collapsible;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final tone = context.appColors.phaseTone(phase);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.section, Gap.lg, Gap.xs),
      child: Row(children: [
        Icon(phaseIcon(phase), size: 20, color: tone.fg),
        const SizedBox(width: Gap.sm),
        Text(phase.label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('$count', style: TextStyle(color: tone.fg, fontWeight: FontWeight.w700, fontSize: 15)),
        if (collapsible) ...[
          const Spacer(),
          Icon(collapsed ? Icons.expand_more : Icons.expand_less),
        ],
      ]),
    );
    return collapsible ? InkWell(onTap: onToggle, child: row) : row;
  }
}

/// 목록 맨 위 "오늘 놓치면 안 되는 청약" 요약 띠. 오늘 마감·임박·접수 중 건수를 한눈에 보여준다.
class TodaySummary extends StatelessWidget {
  const TodaySummary({super.key, required this.counts});
  final Map<Phase, int> counts;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    Widget chip(Phase p, String label) {
      final n = counts[p] ?? 0;
      final tone = colors.phaseTone(p);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm, horizontal: Gap.md),
          decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(Gap.chipRadius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(phaseIcon(p), size: 14, color: tone.fg),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, height: 18 / 12, color: tone.fg, fontWeight: FontWeight.w600)),
            ]),
            Text('$n건',
                style: TextStyle(fontSize: 22, height: 30 / 22, color: tone.fg, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Gap.cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('오늘 놓치면 안 되는 청약',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: Gap.sm),
        Row(children: [
          chip(Phase.closingSoon, '마감 임박'),
          const SizedBox(width: Gap.sm),
          chip(Phase.open, '접수 중'),
          const SizedBox(width: Gap.sm),
          chip(Phase.upcoming, '접수 예정'),
        ]),
      ]),
    );
  }
}

/// 비교에 담은 공고가 1개 이상이면 나타나는 버튼. 2개 이상이면 비교 화면으로 간다.
class CompareFab extends ConsumerWidget {
  const CompareFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(compareSelectionProvider).length;
    if (n == 0) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      heroTag: null, // 탭 두 곳에 동시에 존재하므로 Hero 태그 충돌 방지
      onPressed: () {
        if (n < 2) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('비교하려면 1개 더 담아 주세요')));
        } else {
          context.push('/compare');
        }
      },
      icon: const Icon(Icons.compare_arrows),
      label: Text('비교하기 ($n)'),
    );
  }
}
