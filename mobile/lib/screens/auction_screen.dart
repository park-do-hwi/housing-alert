import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/theme.dart';
import 'web_screen.dart';

class AuctionItem {
  const AuctionItem({required this.id, required this.title, required this.cat, required this.sido, required this.url, this.min, this.apsl, this.end, this.img, this.fail});
  final String id, title, cat, sido, url;
  final int? min, apsl, fail;
  final String? end, img;
}

/// 온비드 공매 물건(주거용). 서버가 모아 auction.json 으로 올린다.
final auctionProvider = FutureProvider<List<AuctionItem>>((ref) async {
  final base = AppConfig.dataBase.replaceAll(RegExp(r'/+$'), '');
  final r = await http.get(Uri.parse('$base/auction.json')).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('공매 정보를 불러오지 못했어요 (${r.statusCode})');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  return [
    for (final x in (j['items'] as List? ?? const []))
      if (x is Map && x['t'] is String && (x['u'] as String?)?.startsWith('http') == true)
        AuctionItem(
          id: '${x['id']}',
          title: x['t'] as String,
          cat: (x['cat'] ?? '') as String,
          sido: (x['sido'] ?? '') as String,
          url: x['u'] as String,
          min: (x['min'] as num?)?.toInt(),
          fail: (x['fail'] as num?)?.toInt(),
          apsl: (x['apsl'] as num?)?.toInt(),
          end: (x['end'] as String?)?.isEmpty == true ? null : x['end'] as String?,
          img: (x['img'] as String?)?.startsWith('http') == true ? x['img'] as String : null,
        ),
  ];
});

String _won(int? v) {
  if (v == null || v <= 0) return '-';
  final eok = v / 100000000;
  if (eok >= 1) return '${eok.toStringAsFixed(eok >= 10 ? 0 : 2)}억';
  return '${(v / 10000).round()}만원';
}

class AuctionScreen extends ConsumerStatefulWidget {
  const AuctionScreen({super.key});
  @override
  ConsumerState<AuctionScreen> createState() => _AuctionScreenState();
}

class _AuctionScreenState extends ConsumerState<AuctionScreen> {
  String? sido;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(auctionProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget msg(String s) => ListView(children: [const SizedBox(height: 120), Center(child: Text(s, textAlign: TextAlign.center, style: t.bodyMedium))]);
    return Scaffold(
      appBar: AppBar(title: const Text('공매 (온비드)')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(auctionProvider.future),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => msg('불러오지 못했어요.\n아직 공매 정보가 준비되지 않았을 수 있어요.'),
          data: (all) {
            if (all.isEmpty) return msg('진행 중인 공매 물건이 없어요.');
            final sidos = {for (final a in all) a.sido}.toList()..sort();
            final list = [for (final a in all) if (sido == null || a.sido == sido) a];
            return ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.section), children: [
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in [null, ...sidos])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(s ?? '전체'), selected: sido == s, onSelected: (_) => setState(() => sido = s)),
                    ),
                ]),
              ),
              for (final a in list)
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WebScreen(url: a.url, title: a.title))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (a.img != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(a.img!, width: 88, height: 66, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(width: 88, height: 66, color: Colors.black12)),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text([a.cat, if (a.end != null) '입찰마감 ${a.end}', if ((a.fail ?? 0) > 0) '유찰 ${a.fail}회'].where((x) => x.isNotEmpty).join(' · '), style: t.bodySmall),
                          const SizedBox(height: 4),
                          Text('최저입찰가 ${_won(a.min)}${a.apsl != null ? '  ·  감정가 ${_won(a.apsl)}' : ''}',
                              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              Text('한국자산관리공사 온비드의 공매 물건이에요(법원경매와 다른 제도). 입찰·권리 확인은 온비드 원문에서 꼭 확인하세요.',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]);
          },
        ),
      ),
    );
  }
}
