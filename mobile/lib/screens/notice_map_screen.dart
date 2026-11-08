import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/format.dart';
import '../core/grouping.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../widgets/kakao_map.dart';
import '../widgets/kakao_pins_map.dart';

/// 접수 중·예정인 공고를 전국 지도에 말풍선으로 보여 준다. 말풍선을 누르면 아래에 요약, 요약을 누르면 상세.
class NoticeMapScreen extends ConsumerStatefulWidget {
  const NoticeMapScreen({super.key});
  @override
  ConsumerState<NoticeMapScreen> createState() => _NoticeMapScreenState();
}

class _NoticeMapScreenState extends ConsumerState<NoticeMapScreen> {
  static const _shown = [Phase.closingSoon, Phase.open, Phase.upcoming];
  final Set<Phase> _on = {..._shown};
  String? _selected;
  bool _kakaoFailed = false;

  MapPin _pin(Notice n, Phase p, DateTime now, Color color) {
    final name = n.title.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    final short = name.length > 9 ? '${name.substring(0, 9)}…' : name;
    final today = DateTime(now.year, now.month, now.day);
    final end = n.applyEnd;
    final start = n.infoDate('apply_start');
    String status;
    if (p == Phase.upcoming && start != null) {
      status = '${start.month}/${start.day}';
    } else if (end != null) {
      final d = DateTime(end.year, end.month, end.day).difference(today).inDays;
      status = d <= 0 ? '오늘' : (d == 1 ? '내일' : 'D-$d');
    } else {
      status = '접수중';
    }
    final kind = n.tags.firstWhere(
      (t) => const ['분양', '무순위', '장기전세', '임대'].contains(t),
      orElse: () => '공고',
    );
    final types = n.types ?? const <HousingType>[];
    final prices = [for (final t in types) if (t.priceMan != null) t.priceMan!];
    String? price;
    if (prices.isNotEmpty) {
      final lo = prices.reduce((a, b) => a < b ? a : b);
      final hi = prices.reduce((a, b) => a > b ? a : b);
      price = lo == hi
          ? fmtPriceShort(hi)
          : '${fmtPriceShort(lo).replaceAll('억', '')}~${fmtPriceShort(hi)}';
    }
    return MapPin(
      id: n.id,
      lat: n.geo!.lat,
      lng: n.geo!.lng,
      color: color,
      kind: kind,
      status: status,
      name: short,
      group: n.sido.isEmpty ? '기타' : n.sido,
      price: price,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final colors = context.appColors;
    final data = ref.watch(noticesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('분양 지도')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('공고를 불러오지 못했어요.')),
        data: (all) {
          final items = <(Notice, Phase)>[
            for (final n in all)
              if (n.geo != null && _on.contains(phaseOf(n, now)))
                (n, phaseOf(n, now)),
          ];
          final pins = [
            for (final (n, p) in items)
              _pin(n, p, now, colors.phaseTone(p).fg),
          ];
          final selected = items.where((e) => e.$1.id == _selected).firstOrNull;
          final key = (_on.map((e) => e.index).toList()..sort()).join(',');
          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    for (final p in _shown)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(p.label),
                          avatar: CircleAvatar(
                            backgroundColor: colors.phaseTone(p).fg,
                            radius: 6,
                          ),
                          selected: _on.contains(p),
                          onSelected: (v) => setState(() {
                            v ? _on.add(p) : _on.remove(p);
                            _selected = null;
                          }),
                        ),
                      ),
                    Center(
                      child: Text(
                        '${pins.length}곳',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    if (kakaoNativeKey.isNotEmpty && !_kakaoFailed)
                      KakaoPinsMap(
                        key: ValueKey(key),
                        pins: pins,
                        onSelect: (id) => setState(() => _selected = id),
                        onFail: () =>
                            mounted ? setState(() => _kakaoFailed = true) : null,
                      )
                    else
                      _OsmPins(
                        pins: pins,
                        onSelect: (id) => setState(() => _selected = id),
                      ),
                    if (selected != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12 + MediaQuery.paddingOf(context).bottom,
                        child: _SelectedCard(
                          notice: selected.$1,
                          phase: selected.$2,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.notice, required this.phase});
  final Notice notice;
  final Phase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = context.appColors.phaseTone(phase);
    final end = notice.applyEnd;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(Gap.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.cardRadius),
        onTap: () => context.push('/notice', extra: notice),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  phase.label,
                  style: TextStyle(
                    color: tone.fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        notice.sido,
                        if (end != null) '마감 ${end.month}.${end.day}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// 카카오 키가 없거나 못 열 때 쓰는 OSM 지도 + 말풍선.
class _OsmPins extends StatelessWidget {
  const _OsmPins({required this.pins, required this.onSelect});
  final List<MapPin> pins;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(36.4, 127.8),
        initialZoom: 6.4,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kr.taskcore.housing_alert',
          tileDimension: 384,
        ),
        MarkerLayer(
          markers: [
            for (final p in pins)
              Marker(
                point: LatLng(p.lat, p.lng),
                width: 28,
                height: 28,
                child: GestureDetector(
                  onTap: () => onSelect(p.id),
                  child: Center(child: PinDot(color: p.color)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
