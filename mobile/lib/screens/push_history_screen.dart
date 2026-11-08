import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import 'web_screen.dart';

class PushEntry {
  const PushEntry({
    required this.id,
    required this.title,
    required this.sido,
    required this.tags,
    required this.url,
    required this.at,
  });
  final String id, title, sido, url;
  final List<String> tags;
  final DateTime? at;
}

/// 서버가 보낸 알림 기록(pushes.json, 최근 100건). 앱이 꺼져 있을 때 온 알림도 여기서 볼 수 있다.
final pushHistoryProvider = FutureProvider.autoDispose<List<PushEntry>>((
  ref,
) async {
  final base = AppConfig.dataBase.replaceAll(RegExp(r'/+$'), '');
  final r = await http
      .get(
        Uri.parse(
          '$base/pushes.json?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
        ),
      )
      .timeout(const Duration(seconds: 20));
  if (r.statusCode == 404) return const [];
  if (r.statusCode != 200) {
    throw Exception('알림 기록을 불러오지 못했어요 (${r.statusCode})');
  }
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  return [
    for (final x in (j['items'] as List? ?? const []))
      if (x is Map)
        PushEntry(
          id: '${x['id'] ?? ''}',
          title: '${x['title'] ?? ''}',
          sido: '${x['sido'] ?? ''}',
          tags: [for (final t in (x['tags'] as List? ?? const [])) '$t'],
          url: '${x['url'] ?? ''}',
          at: DateTime.tryParse('${x['at'] ?? ''}')?.toLocal(),
        ),
  ];
});

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '방금';
  if (d.inMinutes < 60) return '${d.inMinutes}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  if (d.inDays < 7) return '${d.inDays}일 전';
  return '${t.month}.${t.day}';
}

class PushHistoryScreen extends ConsumerWidget {
  const PushHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pushHistoryProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('알림 기록')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: Gap.md),
                OutlinedButton(
                  onPressed: () => ref.invalidate(pushHistoryProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(Gap.lg),
                  child: Text(
                    '아직 받은 알림이 없어요.\n새 공고가 올라오면 여기에도 남아요.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.refresh(pushHistoryProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (context, i) {
                    final e = list[i];
                    final meta = [
                      if (e.sido.isNotEmpty) e.sido,
                      ...e.tags,
                    ].join(' · ');
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        child: Icon(
                          Icons.notifications_outlined,
                          color: cs.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (meta.isNotEmpty) meta,
                          _ago(e.at),
                        ].where((s) => s.isNotEmpty).join('  ·  '),
                      ),
                      onTap: () {
                        final all = ref.read(noticesProvider).value ?? const [];
                        final hit = all.where((n) => n.id == e.id).toList();
                        if (hit.isNotEmpty) {
                          context.push('/notice', extra: hit.first);
                        } else if (e.url.startsWith('http')) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  WebScreen(url: e.url, title: e.title),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }
}
