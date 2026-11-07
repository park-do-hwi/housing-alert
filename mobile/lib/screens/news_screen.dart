import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/theme.dart';

class NewsItem {
  const NewsItem({required this.title, required this.url, required this.source, this.at});
  final String title;
  final String url;
  final String source;
  final DateTime? at;
}

/// 부동산 뉴스(청약·분양·임대·정책). 서버가 30분마다 모아 news.json 으로 올린다.
final newsProvider = FutureProvider<List<NewsItem>>((ref) async {
  final base = AppConfig.dataBase.replaceAll(RegExp(r'/+$'), '');
  final r = await http.get(Uri.parse('$base/news.json')).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('뉴스를 불러오지 못했어요 (${r.statusCode})');
  final list = (jsonDecode(utf8.decode(r.bodyBytes))['items'] as List? ?? const []);
  return [
    for (final j in list)
      if (j is Map && j['t'] is String && (j['u'] as String?)?.startsWith('http') == true)
        NewsItem(
            title: j['t'] as String,
            url: j['u'] as String,
            source: (j['s'] ?? '') as String,
            at: DateTime.tryParse((j['at'] ?? '') as String)?.toLocal()),
  ];
});

String _ago(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  return '${d.inDays}일 전';
}

class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final news = ref.watch(newsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('부동산 뉴스')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(newsProvider.future),
        child: news.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text('뉴스를 불러오지 못했어요.\n아래로 당겨 다시 시도해 주세요.', textAlign: TextAlign.center, style: t.bodyMedium)),
          ]),
          data: (items) => items.isEmpty
              ? ListView(children: [const SizedBox(height: 120), Center(child: Text('아직 뉴스가 없어요.', style: t.bodyMedium))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.section),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = items[i];
                    return InkWell(
                      onTap: () => launchUrl(Uri.parse(n.url), mode: LaunchMode.externalApplication),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n.title, style: t.titleSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text([n.source, _ago(n.at)].where((x) => x.isNotEmpty).join(' · '), style: t.bodySmall),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
