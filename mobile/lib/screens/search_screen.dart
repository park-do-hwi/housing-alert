import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/grouping.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// 공고 검색: 제목·지역·기관 이름에 들어 있는 글자로 찾는다. 접수 중인 것이 위, 마감은 아래.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  String query = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  static bool matches(Notice n, String q) {
    final text = '${n.title} ${n.sido} ${sourceLabel(n.source)} ${n.tags.join(' ')} ${n.str('address') ?? ''}'
        .toLowerCase();
    return q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(text.contains);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ref.watch(noticeDataProvider);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '단지명·지역·기관(LH, SH, GH)으로 검색',
            border: InputBorder.none,
            suffixIcon: query.isEmpty
                ? const Icon(Icons.search)
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      controller.clear();
                      query = '';
                    }),
                  ),
          ),
          onChanged: (v) => setState(() => query = v.trim()),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(noticeDataProvider)),
        data: (d) {
          if (query.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xl),
                child: Text('찾고 싶은 단지 이름이나 지역을 입력해 보세요.\n예: 고덕, 경기 행복주택, LH',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            );
          }
          final found = d.items.where((n) => matches(n, query)).toList();
          if (found.isEmpty) return const Center(child: Text('검색 결과가 없어요'));
          final ordered = [for (final (_, items) in groupNotices(found, now)) ...items];
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: Gap.section),
            itemCount: ordered.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xs),
                  child: Text('${ordered.length}건',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                );
              }
              final n = ordered[i - 1];
              return NoticeTile(notice: n, now: now, onTap: () => context.push('/notice', extra: n));
            },
          );
        },
      ),
    );
  }
}
