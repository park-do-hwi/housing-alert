import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/grouping.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/place_map.dart';
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
        _Hero(notice: notice, badge: badge, tone: tone, phase: phase, now: now),
        const SizedBox(height: Gap.md),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final tag in notice.tags.where((x) => x != '기타')) TagChip(tag),
        ]),
        const SizedBox(height: Gap.md),
        Text(notice.title, style: t.headlineSmall?.copyWith(fontSize: 20, fontWeight: FontWeight.w500, height: 28 / 20)),
        const SizedBox(height: 4),
        Text('${notice.sido.isEmpty ? '' : '${notice.sido} · '}${sourceLabel(notice.source)} · 공고 ${fmtDate(notice.announceDate)}',
            style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: Gap.lg),
        _Summary(notice: notice, now: now),
        const SizedBox(height: Gap.md),
        _Highlights(notice: notice),
        if (notice.geo != null) ...[const SizedBox(height: Gap.md), PlaceMap(notice: notice)],
        if (notice.mkt['per_m2'] is num) ...[const SizedBox(height: Gap.md), _MarketInfo(notice: notice)],
        if (notice.plan != null || notice.plans.isNotEmpty) ...[const SizedBox(height: Gap.md), _PlanImage(notice: notice)],
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
        child: Text(s, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w500)),
      );

  /// 일정: 접수 시작·마감·당첨자 발표·계약 시작 중 실제 값이 있는 것만.
  List<Widget> _schedule(BuildContext context, DateTime now) {
    final stages = stagePeriods(notice);
    final events = <TimelineEvent>[
      if (stages.isNotEmpty)
        for (final st in stages) TimelineEvent(st.label, st.start, end: st.end)
      else ...[
        if (notice.infoDate('apply_start') != null) TimelineEvent('접수 시작', notice.infoDate('apply_start')!),
        if (notice.applyEnd != null) TimelineEvent('접수 마감', notice.applyEnd!),
      ],
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
        if (f is Map && f['url'] != null)
          (name: '${f['name'] ?? '공고문'}', url: '${f['url']}', size: f['size']),
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
            onTap: () => _confirmDownload(context, f.name, f.url, f.size),
          ),
        ),
    ];
  }

  /// 파일은 눌렀다고 바로 받지 않고, 이름·형식·크기를 보여준 뒤 확인을 받는다.
  Future<void> _confirmDownload(BuildContext context, String name, String url, Object? size) async {
    final bytes = size is num ? size.toInt() : int.tryParse('$size');
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('파일을 내려받을까요?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text([_fileKind(name).split(' · ').first, if (bytes != null) fmtBytes(bytes)].join(' · ')),
          const SizedBox(height: 8),
          const Text('브라우저로 열려 기기에 저장될 수 있어요.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('내려받기')),
        ],
      ),
    );
    if (yes == true && context.mounted) await _open(context, url);
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

/// 맨 위 큰 이미지 영역. 사진이 없으면 유형 색 타일(아이콘+시·도)이고, 상태 배지와 NEW 가 위에 얹힌다.
class _Hero extends StatelessWidget {
  const _Hero({required this.notice, required this.badge, required this.tone, required this.phase, required this.now});
  final Notice notice;
  final String? badge;
  final Tone tone;
  final Phase phase;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (_, c) => Stack(children: [
        ApartmentThumb(notice: notice, size: c.maxWidth, height: 168, showRegion: true, highRes: true),
        Positioned(
          left: 10,
          top: 10,
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(Gap.tagRadius)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(phaseIcon(phase), size: 14, color: tone.fg),
                  const SizedBox(width: 4),
                  Text(badge!,
                      style: TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w600, color: tone.fg)),
                ]),
              ),
            if (notice.isNew(now))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(Gap.tagRadius)),
                child: Text('NEW',
                    style: TextStyle(
                        fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onPrimary)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// 한눈에 보기: 공고 데이터에서 핵심만 문장으로 정리한다(없는 값은 빼고, 지어내지 않는다).
class _Summary extends StatelessWidget {
  const _Summary({required this.notice, required this.now});
  final Notice notice;
  final DateTime now;

  List<(IconData, String)> lines() {
    final n = notice;
    final out = <(IconData, String)>[];
    final badge = badgeLabel(n, now);
    final phase = phaseOf(n, now);
    final end = n.applyEnd;
    final start = n.infoDate('apply_start');
    switch (phase) {
      case Phase.closingSoon || Phase.open:
        out.add((Icons.event_available_outlined,
            '지금 접수 중${badge == null ? '' : ' ($badge)'}${end == null ? '' : ' · ${fmtMdW(end)} 마감'}'));
      case Phase.upcoming:
        out.add((Icons.event_outlined,
            '접수 예정${start == null ? '' : ' · ${fmtMdW(start)} 시작'}${end == null ? '' : ' ~ ${fmtMdW(end)}'}'));
      case Phase.closed:
        out.add((Icons.event_busy_outlined, '접수가 끝났어요${end == null ? '' : ' (${fmtMdW(end)} 마감)'}'));
      case Phase.undated:
        out.add((Icons.help_outline, '접수 일정은 원문 공고에서 확인하세요'));
    }
    final tags = n.tags.where((x) => x != '기타').join('·');
    final hh = n.infoInt('total_households');
    final head = [
      if (n.sido.isNotEmpty) n.sido,
      if (tags.isNotEmpty) tags,
    ].join(' ');
    if (head.isNotEmpty || hh != null) {
      out.add((Icons.apartment_outlined, [if (head.isNotEmpty) head, if (hh != null) '총 $hh세대'].join(' · ')));
    }
    final types = n.types;
    if (types != null && types.isNotEmpty) {
      final s = TypeSummary(types);
      final parts = [
        if (s.minArea != null) '전용 ${s.areaRangePy}',
        if (s.minPrice != null) '분양가 ${s.priceRange}',
      ];
      if (parts.isNotEmpty) out.add((Icons.payments_outlined, parts.join(' · ')));
    }
    final win = n.infoDate('winner_date');
    if (win != null) out.add((Icons.emoji_events_outlined, '당첨자 발표 ${fmtMdW(win)}'));
    final ym = n.str('move_in_ym');
    if (ym != null) out.add((Icons.key_outlined, '입주 예정 ${fmtYm(ym)}'));
    final files = n.info['files'];
    if (files is List && files.isNotEmpty) {
      out.add((Icons.description_outlined, '공고문 파일 ${files.length}개 · 아래에서 확인'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('한눈에 보기', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: Gap.sm),
          for (final (icon, text) in lines())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
              ]),
            ),
        ]),
      ),
    );
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
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w500)),
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
            cell('${fmtAreaPy(t.exclusiveArea)}${t.type.isEmpty ? '' : '\n${t.type}'}', align: TextAlign.left),
            cell(fmtPriceMan(t.priceMan)),
            cell(t.total?.toString() ?? '-'),
          ]),
      ],
    );
  }
}


/// 평면도(참고): 이미지 검색 결과라 다른 단지 것이 섞일 수 있다. 주택형(84A 등)을 골라 보고, 누르면 크게 본다.
class _PlanImage extends StatefulWidget {
  const _PlanImage({required this.notice});
  final Notice notice;
  @override
  State<_PlanImage> createState() => _PlanImageState();
}

class _PlanImageState extends State<_PlanImage> {
  int sel = 0;

  Widget _img(String url, {String? hi}) => Image.network(
        hi ?? url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => hi != null ? _img(url) : const SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.notice;
    final plans = n.plans.isNotEmpty ? n.plans : [PlanImage(label: '', img: n.plan!, hi: n.planHi)];
    final cur = plans[sel.clamp(0, plans.length - 1)];
    String py(String label) {
      final m = RegExp(r'^(\d+)').firstMatch(label);
      final a = m == null ? null : double.tryParse(m.group(1)!);
      // 주택형 숫자는 전용면적(㎡). 평으로 바꿔 함께 보여 준다.
      return a == null ? label : '$label · ${pyeong(a)}평';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('평면도 (참고)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      if (plans.length > 1 || plans.first.label.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (var i = 0; i < plans.length; i++)
            ChoiceChip(
              label: Text(py(plans[i].label)),
              selected: i == sel,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => sel = i),
            ),
        ]),
      ],
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(child: _img(cur.img, hi: cur.hi)),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Gap.chipRadius),
          child: SizedBox(
              height: 220,
              width: double.infinity,
              child: ColoredBox(color: Colors.white, child: _img(cur.img, hi: cur.hi))),
        ),
      ),
      const SizedBox(height: 4),
      Text('이미지 검색 결과예요. 다른 단지의 평면도일 수 있으니 정확한 구조는 원문 공고를 확인하세요.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

/// 주변 시세(참고): 같은 시·군·구의 최근 3개월 아파트 매매 실거래(국토교통부) 요약.
class _MarketInfo extends StatelessWidget {
  const _MarketInfo({required this.notice});
  final Notice notice;

  static String _eok(num manwon) {
    final eok = manwon / 10000;
    return eok >= 1 ? '${eok.toStringAsFixed(eok >= 10 ? 0 : 1)}억' : '${manwon.round()}만원';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = notice.mkt;
    final per = (m['per_m2'] as num);
    final avg84 = m['avg84'];
    final rows = <(String, String)>[
      if (avg84 is num) ('전용 84㎡ 안팎 거래가', '약 ${_eok(avg84)}'),
      ('3.3㎡(1평)당', '약 ${_eok(per * 3.3058)}'),
      ('㎡당', '약 ${per.round()}만원'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('주변 시세 (참고)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: theme.textTheme.bodyMedium)),
            Text(v, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      const SizedBox(height: 4),
      Text(
          '${notice.sido} 같은 시·군·구의 ${m['ym'] ?? '최근 3개월'} 아파트 매매 실거래 ${m['n'] ?? ''}건 기준(국토교통부)이에요. '
          '단지 바로 옆 시세가 아니라 참고용이에요.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}
