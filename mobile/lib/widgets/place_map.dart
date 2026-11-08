import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'kakao_map.dart';

const _userAgent = 'kr.taskcore.housing_alert';
const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// 상세 화면의 위치 지도. 지도는 앱 안에서 확대·축소·이동하고, '크게 보기'는 앱 안 전체 화면 지도, 아래 '카카오맵' 줄은 카카오맵 앱을 연다.
class PlaceMap extends StatefulWidget {
  const PlaceMap({super.key, required this.notice});
  final Notice notice;
  @override
  State<PlaceMap> createState() => _PlaceMapState();
}

/// 카카오맵 앱(없으면 웹 지도)에서 그 좌표를 연다. 내 위치가 아니라 공고 위치를 보여 준다.
Future<void> openInKakaoMap(Notice notice) async {
  final g = notice.geo!;
  final name = Uri.encodeComponent(
    notice.title.length > 30 ? notice.title.substring(0, 30) : notice.title,
  );
  try {
    if (await launchUrl(
      Uri.parse('kakaomap://look?p=${g.lat},${g.lng}'),
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }
  } catch (_) {}
  await launchUrl(
    Uri.parse('https://map.kakao.com/link/map/$name,${g.lat},${g.lng}'),
    mode: LaunchMode.externalApplication,
  );
}

/// 카카오 지도(키가 있고 열리면) 또는 OSM 지도. 확대·축소·이동이 된다.
class _MapBody extends StatefulWidget {
  const _MapBody({required this.notice});
  final Notice notice;
  @override
  State<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends State<_MapBody> {
  bool _kakaoFailed = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.notice.geo!;
    final cs = Theme.of(context).colorScheme;
    final center = LatLng(g.lat, g.lng);
    if (kakaoNativeKey.isNotEmpty && !_kakaoFailed) {
      return KakaoNativeMap(
        lat: g.lat,
        lng: g.lng,
        zoom: g.approx ? 13 : 15,
        areaRadius: g.approx ? 1500 : 400,
        onFail: () => mounted ? setState(() => _kakaoFailed = true) : null,
      );
    }
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: g.approx ? 13.4 : 14.8,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.flingAnimation,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: _tiles,
              userAgentPackageName: _userAgent,
              tileDimension: 384,
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: center,
                  radius: g.approx ? 1500 : 400,
                  useRadiusInMeter: true,
                  color: const Color(0x30E53935),
                  borderColor: const Color(0xCCE53935),
                  borderStrokeWidth: 2,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 36,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.location_on, size: 36, color: cs.error),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 4,
          bottom: 2,
          child: Container(
            color: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: const Text(
              '© OpenStreetMap',
              style: TextStyle(fontSize: 9, color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }
}

/// 앱 안에서 보는 전체 화면 지도.
class FullMapScreen extends StatelessWidget {
  const FullMapScreen({super.key, required this.notice});
  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(notice.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => openInKakaoMap(notice),
            child: const Text('카카오맵 앱'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _MapBody(notice: notice)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.place_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      notice.geo!.approx
                          ? '대략적인 위치예요. 정확한 위치는 원문 공고를 확인하세요.'
                          : '${notice.info['address'] ?? notice.sido}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceMapState extends State<PlaceMap> {
  Notice get notice => widget.notice;

  @override
  Widget build(BuildContext context) {
    final g = notice.geo!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Gap.cardRadius),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 240,
            child: Stack(
              children: [
                _MapBody(notice: notice),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    elevation: 2,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FullMapScreen(notice: notice),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen, size: 18),
                            SizedBox(width: 4),
                            Text('크게 보기', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => openInKakaoMap(notice),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      g.approx
                          ? '대략적인 위치예요. 정확한 위치는 원문 공고를 확인하세요.'
                          : '${notice.info['address'] ?? notice.sido}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '카카오맵',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
