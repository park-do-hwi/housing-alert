import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../widgets/common.dart';

/// 2~3개 공고를 나란히 비교한다. 담은 공고는 [compareSelectionProvider]에 있다.
class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(compareSelectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('공고 비교'), actions: [
        if (selected.isNotEmpty)
          TextButton(
            onPressed: () => ref.read(compareSelectionProvider.notifier).clear(),
            child: const Text('비우기'),
          ),
      ]),
      body: selected.length < 2
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('공고 상세에서 "비교 담기"로\n2~3개를 담아 주세요', textAlign: TextAlign.center),
              ),
            )
          : CompareTable(items: selected),
    );
  }
}

/// 비교 표. 가장 유리한 값(최저가, 가장 이른 마감 등)은 따로 강조하지 않고 값만 나란히 둔다.
class CompareTable extends StatelessWidget {
  const CompareTable({super.key, required this.items});
  final List<Notice> items;

  @override
  Widget build(BuildContext context) {
    final summaries = [for (final d in items) d.types == null ? null : TypeSummary(d.types!)];
    final rows = <(String, List<String>)>[
      ('지역', [for (final d in items) d.sido.isEmpty ? '-' : d.sido]),
      ('접수 시작', [for (final d in items) fmtDate(d.infoDate('apply_start'))]),
      ('접수 마감', [for (final d in items) _dday(d)]),
      ('당첨자 발표', [for (final d in items) fmtDate(d.infoDate('winner_date'))]),
      ('공급 세대', [for (final d in items) d.infoInt('total_households')?.toString() ?? '-']),
      ('전용면적', [for (final s in summaries) s?.areaRange ?? '-']),
      ('분양가', [for (final s in summaries) s?.priceRange ?? '-']),
      ('특별공급', [for (final s in summaries) s?.special?.toString() ?? '-']),
      ('입주 예정', [for (final d in items) fmtYm(d.str('move_in_ym'))]),
      ('시공사', [for (final d in items) d.str('builder') ?? '-']),
    ];
    final head = Theme.of(context).textTheme.titleSmall;

    return ListView(padding: const EdgeInsets.all(12), children: [
      Table(
        columnWidths: {
          0: const FixedColumnWidth(72),
          for (var i = 1; i <= items.length; i++) i: const FlexColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        border: TableBorder(horizontalInside: BorderSide(color: Theme.of(context).dividerColor)),
        children: [
          TableRow(children: [
            const SizedBox.shrink(),
            for (final d in items)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(d.title, style: head, maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
          ]),
          for (final (label, values) in rows)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              for (final v in values)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6), child: Text(v)),
            ]),
        ],
      ),
      const SizedBox(height: 16),
      Text('주택형 정보가 없는 공고(LH·SH 등)는 "-"로 표시돼요. 정확한 내용은 원문 공고를 확인하세요.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  static String _dday(Notice d) {
    final dd = ddayLabel(d);
    return '${fmtDate(d.applyEnd)}${dd == null ? '' : '\n($dd)'}';
  }
}
