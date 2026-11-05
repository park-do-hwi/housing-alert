import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../widgets/common.dart';

class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.notice});
  final Notice notice;

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('링크를 열 수 없어요')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(favoritesProvider).contains(notice.id);
    final inCompare = ref.watch(compareSelectionProvider).any((n) => n.id == notice.id);
    final dday = ddayLabel(notice);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text('${sourceLabel(notice.source)} 공고'), actions: [
        IconButton(
          tooltip: saved ? '저장 해제' : '관심 공고로 저장',
          icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
          onPressed: () async {
            try {
              await ref.read(userDataProvider.notifier).toggleFavorite(notice.id);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
              }
            }
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 6, children: [for (final tag in notice.tags) TagChip(tag)]),
        const SizedBox(height: 12),
        Text(notice.title, style: t.titleLarge),
        const SizedBox(height: 16),
        _row('지역', notice.sido.isEmpty ? '-' : notice.sido),
        _row('공고일', fmtDate(notice.announceDate)),
        _row('접수 마감', '${fmtDate(notice.applyEnd)}${dday == null ? '' : '  ($dday)'}'),
        ..._detailSections(context, notice),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _open(context, notice.url),
              icon: const Icon(Icons.open_in_new),
              label: const Text('원문 공고 보기'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              final ok = ref.read(compareSelectionProvider.notifier).toggle(notice);
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('비교는 최대 3개까지 담을 수 있어요')));
              }
            },
            icon: Icon(inCompare ? Icons.check : Icons.compare_arrows),
            label: Text(inCompare ? '비교 담김' : '비교 담기'),
          ),
        ]),
        const SizedBox(height: 16),
        Text('참고용 정보입니다. 자격·일정·유의사항은 반드시 원문 공고에서 확인하세요.',
            style: t.bodySmall),
      ]),
    );
  }

  List<Widget> _detailSections(BuildContext context, Notice d) {
    final t = Theme.of(context).textTheme;
    final rows = <Widget>[
      if (d.infoDate('apply_start') != null) _row('접수 시작', fmtDate(d.infoDate('apply_start'))),
      if (d.infoDate('winner_date') != null) _row('당첨자 발표', fmtDate(d.infoDate('winner_date'))),
      if (d.infoDate('contract_start') != null) _row('계약 시작', fmtDate(d.infoDate('contract_start'))),
      if (d.infoInt('total_households') != null) _row('공급 세대', '${d.infoInt('total_households')}세대'),
      if (d.str('move_in_ym') != null) _row('입주 예정', fmtYm(d.str('move_in_ym'))),
      if (d.str('address') != null) _row('위치', d.str('address')!),
      if (d.str('sponsor') != null) _row('사업주체', d.str('sponsor')!),
      if (d.str('builder') != null) _row('시공사', d.str('builder')!),
      if (d.str('tel') != null) _row('문의', fmtTel(d.str('tel')!)),
    ];
    final types = d.types;
    return [
      ...rows,
      if (types != null && types.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('주택형별 공급', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('금액은 최고 분양가 기준', style: t.bodySmall),
        const SizedBox(height: 8),
        _TypesTable(types),
      ],
    ];
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 80, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v)),
        ]),
      );
}

class _TypesTable extends StatelessWidget {
  const _TypesTable(this.types);
  final List<HousingType> types;

  @override
  Widget build(BuildContext context) {
    final head = Theme.of(context).textTheme.labelMedium;
    Widget cell(String s, {TextStyle? style, TextAlign align = TextAlign.right}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(s, style: style, textAlign: align),
        );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.6),
        2: FlexColumnWidth(0.9),
      },
      border: TableBorder(horizontalInside: BorderSide(color: Theme.of(context).dividerColor)),
      children: [
        TableRow(children: [
          cell('전용', style: head, align: TextAlign.left),
          cell('최고 분양가', style: head),
          cell('세대', style: head),
        ]),
        for (final t in types)
          TableRow(children: [
            cell('${fmtArea(t.exclusiveArea)}${t.type.isEmpty ? '' : '\n${t.type}'}', align: TextAlign.left),
            cell(fmtPriceMan(t.priceMan)),
            cell(t.total?.toString() ?? '-'),
          ]),
      ],
    );
  }
}
