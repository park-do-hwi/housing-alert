import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

/// 카카오맵 네이티브 SDK 지도. 키는 빌드할 때 `--dart-define=KAKAO_NATIVE_KEY=...` 로 준다.
/// 키가 없거나 지도를 못 열면 [onFail] 로 알려, 호출한 쪽이 다른 지도로 바꾼다.
const kakaoNativeKey = String.fromEnvironment('KAKAO_NATIVE_KEY');

Future<void>? _init;
Future<void> kakaoEnsureInit() =>
    _init ??= KakaoMapSdk.instance.initialize(kakaoNativeKey);

class KakaoNativeMap extends StatefulWidget {
  const KakaoNativeMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.onFail,
    this.areaRadius = 0,
  });
  final double lat;
  final double lng;
  final int zoom; // 클수록 확대
  final VoidCallback onFail;
  final double areaRadius; // 분양 지역 영역 반지름(m). 0 이면 표시 안 함

  @override
  State<KakaoNativeMap> createState() => _KakaoNativeMapState();
}

class _KakaoNativeMapState extends State<KakaoNativeMap> {
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

  Future<void> _onReady(KakaoMapController c) async {
    try {
      final pos = LatLng(widget.lat, widget.lng);
      if (widget.areaRadius > 0) {
        try {
          await c.shapeLayer.addPolygonShape(
            CirclePoint(widget.areaRadius, pos),
            PolygonStyle(
              const Color(0x30E53935),
              strokeWidth: 2,
              strokeColor: const Color(0xCCE53935),
            ),
          );
        } catch (_) {}
      }
      final pin = await KImage.fromWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Icon(Icons.location_on, color: Color(0xFFE53935), size: 48),
        ),
        const Size(48, 48),
        context: mounted ? context : null,
      );
      await c.labelLayer.addPoi(pos, style: PoiStyle(icon: pin));
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
      // 화면이 위아래로 스크롤되는 곳이라, 지도를 만지면 지도가 먼저 움직이게 한다(확대·축소·이동).
      forceGesture: true,
      onMapReady: _onReady,
      onMapError: (_) => widget.onFail(),
    );
  }
}
