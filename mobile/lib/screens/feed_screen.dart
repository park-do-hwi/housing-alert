import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config.dart';
import '../core/grouping.dart';
import '../core/models.dart';
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
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.home_work_rounded, size: 22, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('분양 알리미'),
            Text('오늘·이번 주에 해야 할 청약',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ]),
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PopupMenuButton<String?>(
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
                    backgroundColor:
                        filter.sido == null ? null : Theme.of(context).colorScheme.secondaryContainer,
                  ),
                ),
              ),
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
                  : _GroupedList(list: list),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 단계(마감 임박·접수 중·접수 예정…)별 제목줄과 카드를 한 줄로 이어 보여준다.
class _GroupedList extends StatefulWidget {
  const _GroupedList({required this.list});
  final List<Notice> list;

  @override
  State<_GroupedList> createState() => _GroupedListState();
}

class _GroupedListState extends State<_GroupedList> {
  bool closedOpen = false; // 마감 단계는 기본 접힘
  FeedTab? tab; // 숫자 탭 선택. null 이면 전체

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final counts = {for (final t in FeedTab.values) t: widget.list.where((n) => t.matches(n, now)).length};
    final rows = <Object>[counts];
    if (tab != null) {
      final items = groupNotices(widget.list.where((n) => tab!.matches(n, now)).toList(), now)
          .expand((g) => g.$2);
      rows.addAll(items);
    } else {
      for (final (phase, items) in groupNotices(widget.list, now)) {
        rows.add((phase, items.length));
        if (phase != Phase.closed || closedOpen) rows.addAll(items);
      }
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        if (r is Notice) {
          return NoticeTile(notice: r, now: now, onTap: () => context.push('/notice', extra: r));
        }
        if (r is Map<FeedTab, int>) {
          return FeedTabBar(counts: r, selected: tab, onSelect: (t) => setState(() => tab = t));
        }
        final (phase, count) = r as (Phase, int);
        final closed = phase == Phase.closed;
        return PhaseHeader(
          phase: phase,
          count: count,
          collapsible: closed,
          collapsed: !closedOpen,
          onToggle: closed ? () => setState(() => closedOpen = !closedOpen) : null,
        );
      },
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
