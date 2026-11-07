import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/theme.dart';

class NewsItem {
  const NewsItem({required this.title, required this.url, required this.source, this.at, this.img});
  final String title;
  final String url;
  final String source;
  final DateTime? at;
  final String? img; // 영상 썸네일
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

/// 부동산 뉴스·영상(청약·분양·임대·정책). 서버가 30분마다 모아 news.json 으로 올린다.
final newsProvider = FutureProvider<NewsBundle>((ref) async {
  final base = AppConfig.dataBase.replaceAll(RegExp(r'/+$'), '');
  final r = await http.get(Uri.parse('$base/news.json')).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('뉴스를 불러오지 못했어요 (${r.statusCode})');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  return NewsBundle(_parse(j['items']), _parse(j['vids']));
});

String _ago(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  return '${d.inDays}일 전';
}

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});
  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  bool videos = false;

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(newsProvider);
    final t = Theme.of(context).textTheme;
    Widget msg(String s) => ListView(children: [const SizedBox(height: 120), Center(child: Text(s, textAlign: TextAlign.center, style: t.bodyMedium))]);
    return Scaffold(
      appBar: AppBar(title: const Text('뉴스·영상')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('부동산 뉴스'), icon: Icon(Icons.newspaper)),
              ButtonSegment(value: true, label: Text('유튜브 영상'), icon: Icon(Icons.play_circle_outline)),
            ],
            selected: {videos},
            onSelectionChanged: (s) => setState(() => videos = s.first),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(newsProvider.future),
            child: bundle.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => msg('불러오지 못했어요.\n아래로 당겨 다시 시도해 주세요.'),
              data: (b) {
                final list = videos ? b.videos : b.news;
                if (list.isEmpty) return msg(videos ? '아직 영상이 없어요.' : '아직 뉴스가 없어요.');
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.section),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = list[i];
                    return InkWell(
                      onTap: () => _open(n.url),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (n.img != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(alignment: Alignment.center, children: [
                                Image.network(n.img!, width: 128, height: 72, fit: BoxFit.cover,
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
                              Text([n.source, _ago(n.at)].where((x) => x.isNotEmpty).join(' · '), style: t.bodySmall),
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
