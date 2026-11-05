import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/grouping.dart';
import '../core/models.dart';
import '../core/providers.dart';

class TagChip extends StatelessWidget {
  const TagChip(this.tag, {super.key});
  final String tag;

  static Color color(String tag) => switch (tag) {
        '무순위' => const Color(0xFFD84315),
        '장기전세' => const Color(0xFF1565C0),
        '분양' => const Color(0xFF2E7D32),
        '임대' => const Color(0xFF6A1B9A),
        _ => const Color(0xFF546E7A),
      };

  @override
  Widget build(BuildContext context) {
    final c = color(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(tag, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
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

Color phaseColor(Phase p) => switch (p) {
      Phase.closingSoon => const Color(0xFFE53935),
      Phase.open => const Color(0xFF2E7D32),
      Phase.upcoming => const Color(0xFF1E88E5),
      Phase.undated || Phase.closed => const Color(0xFF78909C),
    };

/// 목록 한 건: 제목 + 우측 상태 배지, 지역·출처, 핵심 수치(접수 기간·세대수·분양가), 태그.
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
    final color = phaseColor(phase);
    final theme = Theme.of(context);
    final grey = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);

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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(notice.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text('${notice.sido.isEmpty ? '' : '${notice.sido} · '}${sourceLabel(notice.source)}',
              style: grey),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 14, runSpacing: 2, children: [
              for (final f in facts) Text(f, style: theme.textTheme.bodyMedium),
            ]),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final t in notice.tags.where((t) => t != '정정' && t != '기타')) TagChip(t),
            if (notice.tags.contains('정정')) TagChip('정정'),
          ]),
        ]),
      ),
    );
  }
}

/// 목록의 단계 제목줄: '마감 임박 · 3'.
class PhaseHeader extends StatelessWidget {
  const PhaseHeader({super.key, required this.phase, required this.count});
  final Phase phase;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(phase.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
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
