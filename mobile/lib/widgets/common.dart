import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/grouping.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import 'complex_art.dart';

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
      child: Text(tag, style: TextStyle(fontSize: 11, height: 16 / 11, color: tone.fg, fontWeight: FontWeight.w500)),
    );
  }
}

/// 아파트 이미지 자리. 공고 데이터에 사진이 없어서, 유형 색·아이콘·지역명으로 단지를 구분해 보여준다.
/// 나중에 사진이 생기면 같은 크기의 이미지로 바꿔 끼우면 된다.
class ApartmentThumb extends StatelessWidget {
  const ApartmentThumb({super.key, required this.notice, this.size = 64, this.height, this.showRegion = false});
  final Notice notice;
  final double size; // 가로(높이를 따로 주지 않으면 정사각형)
  final double? height;
  final bool showRegion; // 아이콘 아래에 시·도 이름

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
    final h = height ?? size;
    return Container(
      width: size,
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Gap.chipRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone.bg, tone.fg.withValues(alpha: 0.22)],
        ),
      ),
      child: Stack(alignment: Alignment.center, children: [
        // 공고마다 다르게 그려지는 단지 일러스트.
        Positioned.fill(child: ComplexArt(id: notice.id, tags: notice.tags)),
        // 분양 홈페이지의 대표 이미지가 있으면 위에 덮는다. 불러오는 동안·실패하면 아래 일러스트가 보인다.
        if (notice.photo != null)
          Positioned.fill(
            child: Image.network(
              notice.photo!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              frameBuilder: (_, child, frame, sync) =>
                  AnimatedOpacity(opacity: frame == null && !sync ? 0 : 1, duration: const Duration(milliseconds: 200), child: child),
            ),
          ),
        if (showRegion && notice.sido.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: h * 14 / 72 > 22 ? 22 : h * 14 / 72,
              alignment: Alignment.center,
              color: notice.photo != null ? Colors.black54 : null,
              child: Text(notice.sido,
                  maxLines: 1,
                  style: TextStyle(fontSize: size < 70 ? 10 : 12, height: 1.1, fontWeight: FontWeight.w500, color: Colors.white)),
            ),
          ),
      ]),
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

/// 목록 한 건(카드): 왼쪽 큰 단지 이미지(상태·NEW 배지가 위에 얹힘), 오른쪽에 유형 칩·제목·위치·세대/면적·가격,
/// 아래에 단계별 접수 표(특별공급·1순위·2순위, 없으면 접수 기간 한 줄).
class NoticeTile extends StatelessWidget {
  const NoticeTile({super.key, required this.notice, required this.onTap, this.now});
  final Notice notice;
  final VoidCallback onTap;
  final DateTime? now; // 테스트용. 기본은 현재 시각

  static const double imageW = 72;
  static const double imageH = 72;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final phase = phaseOf(notice, at);
    final badge = badgeLabel(notice, at);
    final tone = context.appColors.phaseTone(phase);
    final theme = Theme.of(context);
    final grey = TextStyle(fontSize: 12, height: 18 / 12, color: theme.colorScheme.onSurfaceVariant);

    final households = notice.infoInt('total_households');
    final types = notice.types;
    final summary = (types == null || types.isEmpty) ? null : TypeSummary(types);
    final size = [
      if (households != null) '$households세대',
      if (summary != null && summary.minArea != null) summary.areaRange,
    ].join(' · ');
    final price = summary == null || summary.minPrice == null ? null : summary.priceRangeShort;
    final stages = stagePeriods(notice);
    final place = '${notice.sido.isEmpty ? '' : '${notice.sido} · '}${sourceLabel(notice.source)}';
    final tags = notice.tags.where((t) => t != '기타').toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 3, Gap.lg, 3),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gap.cardRadius),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ApartmentThumb(notice: notice, size: imageW, height: imageH, showRegion: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 4, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(Gap.tagRadius)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(phaseIcon(phase), size: 12, color: tone.fg),
                            const SizedBox(width: 3),
                            Text(badge,
                                style: TextStyle(
                                    fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w600, color: tone.fg)),
                          ]),
                        ),
                      if (notice.isNew(at))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(Gap.tagRadius)),
                          child: Text('NEW',
                              style: TextStyle(
                                  fontSize: 11,
                                  height: 16 / 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onPrimary)),
                        ),
                      for (final t in tags.where((t) => t != '정정')) TagChip(t),
                      if (tags.contains('정정')) const TagChip('정정'),
                    ]),
                    const SizedBox(height: 2),
                    Text(notice.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontSize: 14, height: 19 / 14, fontWeight: FontWeight.w600)),
                    Text([place, if (size.isNotEmpty) size].join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: grey),
                    if (price != null && price != '-')
                      Text('분양가 $price',
                          style: TextStyle(
                              fontSize: 13,
                              height: 19 / 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary)),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              _StageTable(stages: stages, fallback: periodText(notice), now: at),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 카드 아래 접수 표. 단계가 있으면 줄마다 [이름 · 기간 · 상태], 없으면 접수 기간 한 줄.
class _StageTable extends StatelessWidget {
  const _StageTable({required this.stages, required this.fallback, required this.now});
  final List<StagePeriod> stages;
  final String? fallback;
  final DateTime now;

  static String _range(DateTime s, DateTime e) {
    String f(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    return s == e ? f(s) : '${f(s)}~${f(e)}';
  }

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty && fallback == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    Widget row(String name, String range, String status, int st) {
      final color = st == 0
          ? theme.colorScheme.primary
          : st < 0
              ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
              : theme.colorScheme.onSurface;
      final style = TextStyle(
          fontSize: 12,
          height: 18 / 12,
          fontWeight: st == 0 ? FontWeight.w600 : FontWeight.w500,
          color: color,
          decoration: st < 0 ? TextDecoration.lineThrough : null);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          SizedBox(
              width: 18,
              child: Icon(st == 0 ? Icons.play_arrow_rounded : st < 0 ? Icons.check : Icons.circle_outlined,
                  size: st > 0 ? 10 : 16, color: color)),
          SizedBox(width: 62, child: Text(name, style: style)),
          Expanded(child: Text(range, style: style)),
          Text(status,
              style: TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w500, color: color)),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Gap.chipRadius),
      ),
      child: stages.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(children: [
                Icon(Icons.event_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(fallback!, style: const TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w500)),
              ]),
            )
          : Column(children: [
              for (final s in stages)
                row(s.label, _range(s.start, s.end), switch (s.stateAt(now)) {
                  -1 => '종료',
                  0 => '접수 중',
                  _ => '접수 예정',
                }, s.stateAt(now)),
            ]),
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
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 2),
      child: Row(children: [
        Icon(phaseIcon(phase), size: 18, color: tone.fg),
        const SizedBox(width: Gap.sm),
        Text(phase.label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Text('$count', style: TextStyle(color: tone.fg, fontWeight: FontWeight.w500, fontSize: 15)),
        if (collapsible) ...[
          const Spacer(),
          Icon(collapsed ? Icons.expand_more : Icons.expand_less),
        ],
      ]),
    );
    return collapsible ? InkWell(onTap: onToggle, child: row) : row;
  }
}

/// 목록 맨 위 숫자 탭: 마감 임박·접수 중·접수 예정·무순위·마감 건수. 누르면 그 묶음만 보고, 다시 누르면 전체로 돌아간다.
class FeedTabBar extends StatelessWidget {
  const FeedTabBar({super.key, required this.counts, required this.selected, required this.onSelect});
  final Map<FeedTab, int> counts;
  final FeedTab? selected;
  final ValueChanged<FeedTab?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final toneOf = {
      FeedTab.closingSoon: colors.phaseTone(Phase.closingSoon),
      FeedTab.open: colors.phaseTone(Phase.open),
      FeedTab.upcoming: colors.phaseTone(Phase.upcoming),
      FeedTab.rush: colors.tagTone('무순위'),
      FeedTab.closed: colors.phaseTone(Phase.closed),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
      child: Row(children: [
        for (final t in FeedTab.values) ...[
          if (t != FeedTab.values.first) const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: selected == t ? toneOf[t]!.bg : theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Gap.chipRadius),
                side: BorderSide(
                    color: selected == t ? toneOf[t]!.fg : theme.colorScheme.outlineVariant,
                    width: selected == t ? 1.5 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Gap.chipRadius),
                onTap: () => onSelect(selected == t ? null : t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(t.label,
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 11,
                            height: 16 / 11,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant)),
                    Text('${counts[t] ?? 0}',
                        style: TextStyle(
                            fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w600, color: toneOf[t]!.fg)),
                  ]),
                ),
              ),
            ),
          ),
        ],
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
