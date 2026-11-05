import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class NoticeTile extends StatelessWidget {
  const NoticeTile({super.key, required this.notice, required this.onTap});
  final Notice notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dday = ddayLabel(notice);
    return ListTile(
      onTap: onTap,
      title: Text(notice.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final t in notice.tags.where((t) => t != '정정' && t != '기타')) TagChip(t),
          Text('${notice.source} · ${notice.sido} · ${fmtDate(notice.announceDate)}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      trailing: dday == null
          ? null
          : Text(dday,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: (notice.daysLeft() ?? 9) <= 1 ? Colors.red : null)),
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
