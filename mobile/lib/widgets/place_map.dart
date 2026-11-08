import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'kakao_map.dart';

const _userAgent = 'kr.taskcore.housing_alert';
const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// 상세 화면의 위치 지도. 누르면 카카오맵이 열린다.
class PlaceMap extends StatefulWidget {
  const PlaceMap({super.key, required this.notice});
  final Notice notice;
  @override
  State<PlaceMap> createState() => _PlaceMapState();
}

class _PlaceMapState extends State<PlaceMap> {
  Notice get notice => widget.notice;
  bool _kakaoFailed = false;

  Future<void> _openExternal() async {
    final g = notice.geo!;
    final name = Uri.encodeComponent(
      notice.title.length > 30 ? notice.title.substring(0, 30) : notice.title,
    );
    // 카카오맵 앱이 있으면 그 좌표를 바로 보여 주고(내 위치가 아니라), 없으면 웹 지도로 연다.
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
            height: 240,
            child: kakaoNativeKey.isNotEmpty && !_kakaoFailed
                ? KakaoNativeMap(
                    lat: g.lat,
                    lng: g.lng,
                    zoom: g.approx ? 13 : 16,
                    onTap: _openExternal,
                    onFail: () =>
                        mounted ? setState(() => _kakaoFailed = true) : null,
                  )
                : Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: g.approx ? 13.4 : 15.4,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                          onTap: (_, _) => _openExternal(),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: _tiles,
                            userAgentPackageName: _userAgent,
                            tileDimension: 384,
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
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black87,
                            ),
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
