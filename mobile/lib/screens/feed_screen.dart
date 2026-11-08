import 'notice_map_screen.dart';
import 'push_history_screen.dart';

import 'package:flutter/material.dart';

import 'search_screen.dart';

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
        title: Row(
          children: [
            Image.asset(
              'assets/brand/logo.png',
              width: 38,
              height: 38,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('청약레이더'),
                Text(
                  '오늘·이번 주에 해야 할 청약',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // 공매(경매)는 2차 버전에서. 화면 코드는 auction_screen.dart 에 남겨 둔다.
          IconButton(
            tooltip: '공고 검색',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            tooltip: '알림 기록',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PushHistoryScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: '분양 지도',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NoticeMapScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () async {
                      final r = await showDialog<List<String?>>(
                        context: context,
                        builder: (c) =>
                            _SidoDialog(current: filter.sido, list: sidoList),
                      );
                      if (r != null)
                        setFilter(
                          r.first == null
                              ? filter.copyWith(clearSido: true)
                              : filter.copyWith(sido: r.first),
                        );
                    },
                    child: Chip(
                      avatar: const Icon(Icons.place, size: 16),
                      label: Text(filter.sido ?? '전국'),
                      backgroundColor: filter.sido == null
                          ? null
                          : Theme.of(context).colorScheme.secondaryContainer,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: const Icon(Icons.favorite_border, size: 16),
                    label: const Text('내 조건'),
                    selected: filter.mineOnly,
                    onSelected: (on) =>
                        setFilter(filter.copyWith(mineOnly: on)),
                  ),
                ),
                for (final c in categoryList)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: filter.category == c,
                      onSelected: (on) => setFilter(
                        on
                            ? filter.copyWith(category: c)
                            : filter.copyWith(clearCategory: true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (data != null)
            _UpdatedBar(data.generatedAt, data.stale, notices.value?.length),
          Expanded(
            child: notices.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                error: e,
                onRetry: () => ref.invalidate(noticeDataProvider),
              ),
              data: (list) => RefreshIndicator(
                onRefresh: () => ref.refresh(noticeDataProvider.future),
                child: list.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('조건에 맞는 공고가 없어요')),
                        ],
                      )
                    : _GroupedList(list: list),
              ),
            ),
          ),
        ],
      ),
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
    final counts = {
      for (final t in FeedTab.values)
        t: widget.list.where((n) => t.matches(n, now)).length,
    };
    final rows = <Object>[counts];
    if (tab != null) {
      final items = groupNotices(
        widget.list.where((n) => tab!.matches(n, now)).toList(),
        now,
      ).expand((g) => g.$2);
      final list = items.toList();
      rows.addAll(list);
      if (list.isEmpty) rows.add(tab!); // 고른 묶음에 공고가 없으면 안내 문구를 보여 준다
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
          return NoticeTile(
            notice: r,
            now: now,
            onTap: () => context.push('/notice', extra: r),
          );
        }
        if (r is Map<FeedTab, int>) {
          return FeedTabBar(
            counts: r,
            selected: tab,
            onSelect: (t) => setState(() => tab = t),
          );
        }
        if (r is FeedTab) return _EmptyTab(tab: r);
        final (phase, count) = r as (Phase, int);
        final closed = phase == Phase.closed;
        return PhaseHeader(
          phase: phase,
          count: count,
          collapsible: closed,
          collapsed: !closedOpen,
          onToggle: closed
              ? () => setState(() => closedOpen = !closedOpen)
              : null,
        );
      },
    );
  }
}

/// 숫자 탭을 눌렀는데 그 묶음에 공고가 없을 때의 안내.
class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.tab});
  final FeedTab tab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = switch (tab) {
      FeedTab.closingSoon => '마감이 임박한 공고가 없어요',
      FeedTab.open => '지금 접수 중인 공고가 없어요',
      FeedTab.upcoming => '접수 예정인 공고가 없어요',
      FeedTab.rush => '접수할 수 있는 무순위 공고가 없어요',
      FeedTab.closed => '마감된 공고가 없어요',
    };
    // 화면 한가운데쯤에 오도록 남은 높이를 대략 채운다.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.5,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(msg, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '위 숫자를 다시 누르면 전체 공고로 돌아가요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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
        stale
            ? '오프라인이에요. 마지막으로 받은 공고를 보여드려요 ($when)'
            : '$when${count == null ? '' : ' · $count건'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// 지역 선택: 목록 대신 표(격자) 형태의 팝업.
class _SidoDialog extends StatelessWidget {
  const _SidoDialog({required this.current, required this.list});
  final String? current;
  final List<String> list;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = <String?>[null, ...list];
    Widget cell(String? v) {
      final on = v == current;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(context, <String?>[v]),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: on ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            v ?? '전국',
            style: TextStyle(
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              color: on ? cs.onPrimary : cs.onSurface,
            ),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('지역 선택', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Table(
                  children: [
                    for (var i = 0; i < all.length; i += 3)
                      TableRow(
                        children: [
                          for (var j = i; j < i + 3; j++)
                            Padding(
                              padding: const EdgeInsets.all(3),
                              child: j < all.length
                                  ? cell(all[j])
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
