import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/grouping.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/timeline.dart';

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
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final phase = phaseOf(notice, now);
    final badge = badgeLabel(notice, now);
    final tone = context.appColors.phaseTone(phase);

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
      body: ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.section), children: [
        Row(children: [
          ApartmentThumb(notice: notice, size: 48),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final tag in notice.tags.where((x) => x != '기타')) TagChip(tag),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(Gap.tagRadius)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(phaseIcon(phase), size: 14, color: tone.fg),
                    const SizedBox(width: 4),
                    Text(badge,
                        style: TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w700, color: tone.fg)),
                  ]),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: Gap.md),
        Text(notice.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 32 / 24)),
        const SizedBox(height: 4),
        Text('${notice.sido.isEmpty ? '' : '${notice.sido} · '}${sourceLabel(notice.source)} · 공고 ${fmtDate(notice.announceDate)}',
            style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: Gap.lg),
        _Highlights(notice: notice),
        ..._schedule(context, now),
        ..._types(context),
        ..._files(context),
        const SizedBox(height: Gap.sm),
        _MoreInfo(notice: notice),
        const SizedBox(height: Gap.lg),
        Text('참고용 정보입니다. 자격·일정·유의사항은 반드시 원문 공고에서 확인하세요.',
            style: t.bodySmall?.copyWith(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _open(context, notice.url),
                icon: const Icon(Icons.open_in_new),
                label: const Text('원문 공고 보기'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
            const SizedBox(width: Gap.sm),
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
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.only(top: Gap.section, bottom: Gap.sm),
        child: Text(s, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
      );

  /// 일정: 접수 시작·마감·당첨자 발표·계약 시작 중 실제 값이 있는 것만.
  List<Widget> _schedule(BuildContext context, DateTime now) {
    final events = <TimelineEvent>[
      if (notice.infoDate('apply_start') != null) TimelineEvent('접수 시작', notice.infoDate('apply_start')!),
      if (notice.applyEnd != null) TimelineEvent('접수 마감', notice.applyEnd!),
      if (notice.infoDate('winner_date') != null) TimelineEvent('당첨자 발표', notice.infoDate('winner_date')!),
      if (notice.infoDate('contract_start') != null) TimelineEvent('계약 시작', notice.infoDate('contract_start')!),
    ];
    if (events.isEmpty) return const [];
    return [
      _sectionTitle(context, '청약 일정'),
      ScheduleTimeline(events: events, now: now),
    ];
  }

  List<Widget> _types(BuildContext context) {
    final types = notice.types;
    if (types == null || types.isEmpty) return const [];
    return [
      _sectionTitle(context, '주택형별 공급'),
      Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text('${types.length}개 주택형 · 금액은 최고 분양가 기준'),
          children: [Padding(padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md), child: _TypesTable(types))],
        ),
      ),
    ];
  }

  /// 공고문 파일(PDF·HWP 등). 수집기가 `info.files`([{name,url}])를 채워 주면 보인다.
  List<Widget> _files(BuildContext context) {
    final raw = notice.info['files'];
    if (raw is! List || raw.isEmpty) return const [];
    final files = [
      for (final f in raw)
        if (f is Map && f['url'] != null) (name: '${f['name'] ?? '공고문'}', url: '${f['url']}'),
    ];
    if (files.isEmpty) return const [];
    return [
      _sectionTitle(context, '공고문 파일'),
      for (final f in files)
        Card(
          margin: const EdgeInsets.only(bottom: Gap.sm),
          child: ListTile(
            minVerticalPadding: 12,
            leading: Icon(_fileIcon(f.name)),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(_fileKind(f.name)),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, f.url),
          ),
        ),
    ];
  }

  static IconData _fileIcon(String name) =>
      name.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.description_outlined;

  static String _fileKind(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'PDF';
    if (n.endsWith('.hwp') || n.endsWith('.hwpx')) return '한글(HWP) · 한글 뷰어 앱이 필요할 수 있어요';
    return '첨부 파일';
  }
}

/// 핵심 3칸: 접수 기간 · 분양가 · 공급 세대. 큰 글자에서는 세로로 쌓는다.
class _Highlights extends StatelessWidget {
  const _Highlights({required this.notice});
  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final s = notice.infoDate('apply_start');
    final e = notice.applyEnd;
    final period = s != null && e != null
        ? (s == e ? fmtMd(e) : '${fmtMd(s)} ~ ${fmtMd(e)}')
        : e != null
            ? '~ ${fmtMd(e)}'
            : s != null
                ? '${fmtMd(s)} ~'
                : '미확인';
    final types = notice.types;
    final price = (types == null || types.isEmpty) ? null : TypeSummary(types).priceRangeShort;
    final hh = notice.infoInt('total_households');

    final cells = [
      _cell(context, Icons.event_outlined, '접수 기간', period),
      _cell(context, Icons.payments_outlined, '분양가', price == null || price == '-' ? '미공개' : price),
      _cell(context, Icons.apartment_outlined, '공급 세대', hh == null ? '-' : '$hh세대'),
    ];
    final bigText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    if (bigText) {
      return Column(children: [for (final c in cells) Padding(padding: const EdgeInsets.only(bottom: Gap.sm), child: c)]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: Gap.sm),
          Expanded(child: cells[i]),
        ],
      ]),
    );
  }

  Widget _cell(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Gap.chipRadius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: TextStyle(fontSize: 12, height: 18 / 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// 부가 정보(기본 접힘): 위치·사업주체·시공사·입주 예정·문의.
class _MoreInfo extends StatelessWidget {
  const _MoreInfo({required this.notice});
  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final d = notice;
    final rows = <(String, String)>[
      if (d.str('address') != null) ('위치', d.str('address')!),
      if (d.str('sponsor') != null) ('사업주체', d.str('sponsor')!),
      if (d.str('builder') != null) ('시공사', d.str('builder')!),
      if (d.str('move_in_ym') != null) ('입주 예정', fmtYm(d.str('move_in_ym'))),
      if (d.str('tel') != null) ('문의', fmtTel(d.str('tel')!)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('부가 정보'),
        subtitle: const Text('위치 · 사업주체 · 입주 예정 · 문의'),
        childrenPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 76,
                    child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                Expanded(child: Text(v)),
              ]),
            ),
        ],
      ),
    );
  }
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
