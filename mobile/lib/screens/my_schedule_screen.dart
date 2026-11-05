import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../widgets/common.dart';

/// 저장한 공고를 일정 상태별로 묶어서 보여준다: 접수 중 / 마감일 정보 없음 / 마감됨.
class MyScheduleScreen extends ConsumerWidget {
  const MyScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteNoticesProvider);
    return Scaffold(
      floatingActionButton: const CompareFab(),
      appBar: AppBar(title: const Text('내 일정')),
      body: favs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(noticeDataProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('공고 상세에서 북마크 버튼을 눌러\n관심 공고를 저장해 보세요',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final open = list.where((n) => n.daysLeft() != null).toList();
          final noDate = list.where((n) => n.applyEnd == null).toList();
          final closed = list.where((n) => n.applyEnd != null && n.daysLeft() == null).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(noticeDataProvider.future),
            child: ListView(children: [
              _section(context, '접수 중 · 마감 임박순', open),
              _section(context, '마감일 정보 없음', noDate),
              _section(context, '마감됨', closed),
            ]),
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Notice> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('$title (${items.length})', style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final n in items) ...[
        NoticeTile(notice: n, onTap: () => context.push('/notice', extra: n)),
        const Divider(height: 1),
      ],
    ]);
  }
}
