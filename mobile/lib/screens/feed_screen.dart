import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config.dart';
import '../core/providers.dart';
import '../widgets/common.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notices = ref.watch(noticesProvider);
    final data = ref.watch(noticeDataProvider).value;
    void setFilter(f) => ref.read(filterProvider.notifier).set(f);

    return Scaffold(
      floatingActionButton: const CompareFab(),
      appBar: AppBar(title: const Text('분양·무순위 공고')),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: const Icon(Icons.favorite_border, size: 16),
                  label: const Text('내 조건'),
                  selected: filter.mineOnly,
                  onSelected: (on) => setFilter(filter.copyWith(mineOnly: on)),
                ),
              ),
              for (final c in categoryList)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: filter.category == c,
                    onSelected: (on) => setFilter(
                        on ? filter.copyWith(category: c) : filter.copyWith(clearCategory: true)),
                  ),
                ),
              PopupMenuButton<String?>(
                tooltip: '지역',
                onSelected: (v) =>
                    setFilter(v == null ? filter.copyWith(clearSido: true) : filter.copyWith(sido: v)),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('전국')),
                  for (final s in sidoList) PopupMenuItem(value: s, child: Text(s)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.place, size: 16),
                  label: Text(filter.sido ?? '전국'),
                ),
              ),
            ],
          ),
        ),
        if (data != null) _UpdatedBar(data.generatedAt, data.stale, notices.value?.length),
        Expanded(
          child: notices.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(noticeDataProvider)),
            data: (list) => RefreshIndicator(
              onRefresh: () => ref.refresh(noticeDataProvider.future),
              child: list.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('조건에 맞는 공고가 없어요')),
                    ])
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => NoticeTile(
                        notice: list[i],
                        onTap: () => context.push('/notice', extra: list[i]),
                      ),
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _UpdatedBar extends StatelessWidget {
  const _UpdatedBar(this.at, this.stale, this.count);
  final DateTime? at;
  final bool stale;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = at?.toLocal();
    final when = t == null
        ? ''
        : '${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')} '
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} 기준';
    return Container(
      width: double.infinity,
      color: stale ? Theme.of(context).colorScheme.errorContainer : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        stale ? '오프라인이에요. 마지막으로 받은 공고를 보여드려요 ($when)' : '$when${count == null ? '' : ' · $count건'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
