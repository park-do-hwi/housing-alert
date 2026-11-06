import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/theme.dart';

const _userAgent = 'kr.taskcore.housing_alert';
const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// 상세 화면의 위치 지도. 누르면 카카오맵이 열린다.
class PlaceMap extends StatelessWidget {
  const PlaceMap({super.key, required this.notice});
  final Notice notice;

  Future<void> _openExternal() async {
    final g = notice.geo!;
    final name = Uri.encodeComponent(
      notice.title.length > 30 ? notice.title.substring(0, 30) : notice.title,
    );
    await launchUrl(
      Uri.parse('https://map.kakao.com/link/map/$name,${g.lat},${g.lng}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = notice.geo!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final center = LatLng(g.lat, g.lng);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Gap.cardRadius),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: g.approx ? 14 : 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    onTap: (_, _) => _openExternal(),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tiles,
                      userAgentPackageName: _userAgent,
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: center,
                          width: 36,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: Icon(
                            Icons.location_on,
                            size: 36,
                            color: cs.error,
                          ),
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
            ),
          ),
          InkWell(
            onTap: _openExternal,
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

/// 목록 카드용 작은 지도 조각. OpenStreetMap 타일 한 장에서 위치 주변만 잘라 보여 준다.
/// 정확한 위치(주소)는 가깝게(z16), 대략 위치는 넓게(z14) 보여 준다.
class MapTile extends StatelessWidget {
  const MapTile({
    super.key,
    required this.geo,
    required this.width,
    required this.height,
    required this.pinColor,
  });
  final GeoPoint geo;
  final double width;
  final double height;
  final Color pinColor;

  static const _tile = 256.0;

  /// (타일 x, 타일 y, 타일 안에서의 위치 px x, y)
  static (int, int, double, double) locate(GeoPoint g, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    final latRad = g.lat * math.pi / 180;
    final x = (g.lng + 180) / 360 * n;
    final y =
        (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
        2 *
        n;
    return (
      x.floor(),
      y.floor(),
      (x - x.floor()) * _tile,
      (y - y.floor()) * _tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final zoom = geo.approx ? 14 : 16;
    final (tx, ty, px, py) = locate(geo, zoom);
    // 창이 타일 밖으로 나가지 않게 맞춘다(가장자리 근처면 핀이 가운데에서 조금 벗어난다).
    final ox = (px - width / 2).clamp(0.0, _tile - width);
    final oy = (py - height / 2).clamp(0.0, _tile - height);
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            left: -ox,
            top: -oy,
            width: _tile,
            height: _tile,
            child: Image.network(
              'https://tile.openstreetmap.org/$zoom/$tx/$ty.png',
              headers: const {'User-Agent': _userAgent},
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Positioned(
            left: px - ox - 10,
            top: py - oy - 20,
            child: Icon(
              Icons.location_on,
              size: 20,
              color: pinColor,
              shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
            ),
          ),
        ],
      ),
    );
  }
}
