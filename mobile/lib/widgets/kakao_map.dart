import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

/// 카카오맵 네이티브 SDK 지도. 키는 빌드할 때 `--dart-define=KAKAO_NATIVE_KEY=...` 로 준다.
/// 키가 없거나 지도를 못 열면 [onFail] 로 알려, 호출한 쪽이 다른 지도로 바꾼다.
const kakaoNativeKey = String.fromEnvironment('KAKAO_NATIVE_KEY');

Future<void>? _init;
Future<void> _ensureInit() =>
    _init ??= KakaoMapSdk.instance.initialize(kakaoNativeKey);

class KakaoNativeMap extends StatefulWidget {
  const KakaoNativeMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.onTap,
    required this.onFail,
  });
  final double lat;
  final double lng;
  final int zoom; // 클수록 확대
  final VoidCallback onTap;
  final VoidCallback onFail;

  @override
  State<KakaoNativeMap> createState() => _KakaoNativeMapState();
}

class _KakaoNativeMapState extends State<KakaoNativeMap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ensureInit()
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
      final pin = await KImage.fromWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Icon(Icons.location_on, color: Color(0xFFE53935), size: 48),
        ),
        const Size(48, 48),
        context: mounted ? context : null,
      );
      await c.labelLayer.addPoi(pos, style: PoiStyle(icon: pin));
      for (final g in GestureType.values) {
        await c.setGesture(g, false);
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
      onMapReady: _onReady,
      onMapClick: (_, _) => widget.onTap(),
      onMapError: (_) => widget.onFail(),
    );
  }
}
