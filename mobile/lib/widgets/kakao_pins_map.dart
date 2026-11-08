import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import 'kakao_map.dart';

/// 지도에 찍을 공고 하나.
class MapPin {
  const MapPin({
    required this.id,
    required this.lat,
    required this.lng,
    required this.color,
    required this.kind,
    required this.status,
    required this.name,
    required this.group,
    this.price,
  });
  final String id;
  final double lat;
  final double lng;
  final Color color; // 접수 상태 색
  final String kind; // 분양 종류: 분양·무순위·임대·장기전세
  final String status; // 크게 보일 글: D-3, 오늘, 11/17 …
  final String name; // 공고명(짧게)
  final String group; // 묶음(시·도)
  final String? price; // 분양가(짧게)
}

/// 멀리서 보는 작은 점.
class PinDot extends StatelessWidget {
  const PinDot({super.key, required this.color});
  final Color color;
  static const size = Size(14, 14);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}

/// 아주 멀리서 보는 묶음 원: 시·도 이름과 개수.
class PinCluster extends StatelessWidget {
  const PinCluster({super.key, required this.name, required this.count});
  final String name;
  final int count;

  static Size sizeFor(int count) {
    final d = (28 + count * 0.5).clamp(28.0, 38.0);
    return Size(d, d);
  }

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(count);
    const base = TextStyle(
      color: Colors.white,
      decoration: TextDecoration.none,
      height: 1.1,
    );
    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xE61D4ED8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            textDirection: TextDirection.ltr,
            style: base.copyWith(fontSize: 8, fontWeight: FontWeight.w400),
          ),
          Text(
            '$count',
            textDirection: TextDirection.ltr,
            style: base.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// 가까이서 보는 카드: 위 색 띠(분양 종류) / 흰 칸(크게 D-일수) / 꼬리 / 아래에 이름과 분양가.
class PinCard extends StatelessWidget {
  const PinCard({super.key, required this.pin});
  final MapPin pin;

  static const _w = 50.0;
  static const _head = 11.0;
  static const _body = 18.0;
  static const _tail = 4.0;

  static Size sizeFor(MapPin p) =>
      Size(86, _head + _body + _tail + 11 + (p.price != null ? 11 : 0));

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(pin);
    const base = TextStyle(decoration: TextDecoration.none, height: 1.1);
    final halo = [
      for (final o in const [Offset(-1, 0), Offset(1, 0), Offset(0, -1), Offset(0, 1)])
        Shadow(color: Colors.white, offset: o),
    ];
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        children: [
          Container(
            width: _w,
            height: _head + _body,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: pin.color, width: 1),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  height: _head - 1,
                  width: double.infinity,
                  color: pin.color,
                  alignment: Alignment.center,
                  child: Text(
                    pin.kind,
                    maxLines: 1,
                    textDirection: TextDirection.ltr,
                    style: base.copyWith(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      pin.status,
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                      style: base.copyWith(
                        color: pin.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(size: const Size(7, _tail), painter: _Tail(pin.color)),
          Text(
            pin.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: base.copyWith(
              color: const Color(0xFF222222),
              fontSize: 8,
              fontWeight: FontWeight.w400,
              shadows: halo,
            ),
          ),
          if (pin.price != null)
            Text(
              pin.price!,
              maxLines: 1,
              textDirection: TextDirection.ltr,
              style: base.copyWith(
                color: const Color(0xFF1D4ED8),
                fontSize: 8,
                fontWeight: FontWeight.w500,
                shadows: halo,
              ),
            ),
        ],
      ),
    );
  }
}

class _Tail extends CustomPainter {
  _Tail(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Tail old) => old.color != color;
}

/// 카카오 지도에 공고를 찍는다. 확대 정도에 따라 모양이 바뀐다.
///  - 멀리: 시·도별 묶음 원(개수)
///  - 중간: 작은 점
///  - 가까이: 카드(분양 종류·D-일수·이름·분양가)
/// 점·카드를 누르면 [onSelect] 로 id 를 알려주고, 묶음 원을 누르면 그 곳으로 확대한다.
/// 키가 없거나 지도를 못 열면 [onFail] 로 알려, 호출한 쪽이 다른 지도로 바꾼다.
class KakaoPinsMap extends StatefulWidget {
  const KakaoPinsMap({
    super.key,
    required this.pins,
    required this.onSelect,
    required this.onFail,
    this.lat = 36.4,
    this.lng = 127.8,
    this.zoom = 6,
    this.dotZoom = 7,
    this.cardZoom = 10,
  });
  final List<MapPin> pins;
  final void Function(String id) onSelect;
  final VoidCallback onFail;
  final double lat;
  final double lng;
  final int zoom;
  final int dotZoom; // 이보다 확대하면 묶음 대신 점
  final int cardZoom; // 이보다 확대하면 카드

  @override
  State<KakaoPinsMap> createState() => _KakaoPinsMapState();
}

class _KakaoPinsMapState extends State<KakaoPinsMap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    kakaoEnsureInit()
        .then((_) {
          if (mounted) setState(() => _ready = true);
        })
        .catchError((Object _) {
          if (mounted) widget.onFail();
        });
  }

  Future<KImage> _img(Widget w, Size size) => KImage.fromWidget(
        Directionality(textDirection: TextDirection.ltr, child: w),
        size,
        context: context,
      );

  Future<void> _onReady(KakaoMapController c) async {
    try {
      final blank = await _img(const SizedBox(width: 2, height: 2), const Size(2, 2));
      // 시·도별 묶음 원: 멀리서만 보이고, 확대하면 점·카드로 바뀐다.
      final groups = <String, List<MapPin>>{};
      for (final p in widget.pins) {
        groups.putIfAbsent(p.group, () => []).add(p);
      }
      for (final e in groups.entries) {
        if (!mounted) return;
        final lat = e.value.map((p) => p.lat).reduce((a, b) => a + b) / e.value.length;
        final lng = e.value.map((p) => p.lng).reduce((a, b) => a + b) / e.value.length;
        final at = LatLng(lat, lng);
        final style = PoiStyle(
          icon: await _img(
            PinCluster(name: e.key, count: e.value.length),
            PinCluster.sizeFor(e.value.length),
          ),
          anchor: const KPoint(0.5, 0.5),
        );
        style.addStyle(zoomLevel: widget.dotZoom, icon: blank);
        await c.labelLayer.addPoi(
          at,
          style: style,
          onClick: () => c.moveCamera(
            CameraUpdate.newCenterPosition(at, zoomLevel: widget.dotZoom + 2),
            animation: const CameraAnimation(500),
          ),
        );
      }
      // 공고: 멀리서는 안 보이고(투명), 중간은 점, 가까이는 카드.
      for (final p in widget.pins) {
        if (!mounted) return;
        final style = PoiStyle(icon: blank, anchor: const KPoint(0.5, 0.5));
        style.addStyle(
          zoomLevel: widget.dotZoom,
          icon: await _img(PinDot(color: p.color), PinDot.size),
        );
        style.addStyle(
          zoomLevel: widget.cardZoom,
          icon: await _img(PinCard(pin: p), PinCard.sizeFor(p)),
          anchor: const KPoint(0.5, 0.0),
        );
        await c.labelLayer.addPoi(
          LatLng(p.lat, p.lng),
          style: style,
          onClick: () => widget.onSelect(p.id),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return KakaoMap(
      option: KakaoMapOption(
        position: LatLng(widget.lat, widget.lng),
        zoomLevel: widget.zoom,
        mapType: MapType.normal,
      ),
      forceGesture: true,
      onMapReady: _onReady,
      onMapError: (_) => widget.onFail(),
    );
  }
}
