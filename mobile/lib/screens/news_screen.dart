import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/theme.dart';
import 'web_screen.dart';

class NewsItem {
  const NewsItem({required this.title, required this.url, required this.source, this.at, this.img});
  final String title;
  final String url;
  final String source;
  final DateTime? at;
  final String? img; // 영상 썸네일(있으면 영상)
}

class NewsBundle {
  const NewsBundle(this.news, this.videos);
  final List<NewsItem> news;
  final List<NewsItem> videos;
}

List<NewsItem> _parse(dynamic list) => [
      for (final j in (list as List? ?? const []))
        if (j is Map && j['t'] is String && (j['u'] as String?)?.startsWith('http') == true)
          NewsItem(
              title: j['t'] as String,
              url: j['u'] as String,
              source: (j['s'] ?? '') as String,
              at: DateTime.tryParse((j['at'] ?? '') as String)?.toLocal(),
              img: (j['img'] as String?)?.startsWith('https://') == true ? j['img'] as String : null),
    ];

/// 청약·분양·임대 뉴스와 영상. 서버가 30분마다 모아 news.json 으로 올린다.
final newsProvider = FutureProvider<NewsBundle>((ref) async {
  final base = AppConfig.dataBase.replaceAll(RegExp(r'/+$'), '');
  final r = await http.get(Uri.parse('$base/news.json')).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('뉴스를 불러오지 못했어요 (${r.statusCode})');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  return NewsBundle(_parse(j['items']), _parse(j['vids']));
});

String _group(DateTime? at) {
  if (at == null) return '이전';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return now.difference(at).inHours < 3 ? '방금 전 (3시간 이내)' : '오늘';
  if (days == 1) return '어제';
  if (days < 7) return '이번 주';
  return '이전';
}

String _ago(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  return '${d.inDays}일 전';
}

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});
  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  int mode = 0; // 0 전체, 1 뉴스, 2 영상

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(newsProvider);
    final t = Theme.of(context).textTheme;
    Widget msg(String s) =>
        ListView(children: [const SizedBox(height: 120), Center(child: Text(s, textAlign: TextAlign.center, style: t.bodyMedium))]);
    return Scaffold(
      appBar: AppBar(title: const Text('뉴스·영상')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
          child: Row(children: [
            for (final (i, l) in const [(0, '전체'), (1, '뉴스'), (2, '영상')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(l), selected: mode == i, onSelected: (_) => setState(() => mode = i)),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(newsProvider.future),
            child: bundle.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => msg('불러오지 못했어요.\n아래로 당겨 다시 시도해 주세요.'),
              data: (b) {
                final list = [if (mode != 2) ...b.news, if (mode != 1) ...b.videos]
                  ..sort((x, y) => (y.at ?? DateTime(2000)).compareTo(x.at ?? DateTime(2000)));
                if (list.isEmpty) return msg('아직 소식이 없어요.');
                final rows = <Object>[]; // 구간 제목(String)과 항목(NewsItem)이 섞인 목록
                String? last;
                for (final n in list) {
                  final g = _group(n.at);
                  if (g != last) rows.add(g);
                  last = g;
                  rows.add(n);
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.section),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    if (r is String) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 4),
                        child: Text(r, style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                      );
                    }
                    final n = r as NewsItem;
                    return InkWell(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => WebScreen(url: n.url, title: n.title))),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (n.img != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(alignment: Alignment.center, children: [
                                Image.network(hqThumb(n.url, n.img!), width: 128, height: 72, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(width: 128, height: 72, color: Colors.black12)),
                                const Icon(Icons.play_circle_fill, size: 28, color: Colors.white70),
                              ]),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(n.title, style: t.titleSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text([n.img != null ? '영상' : '뉴스', n.source, _ago(n.at)].where((x) => x.isNotEmpty).join(' · '),
                                  style: t.bodySmall),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
