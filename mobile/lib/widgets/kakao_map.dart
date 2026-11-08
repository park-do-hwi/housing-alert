import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 카카오맵 자바스크립트 SDK 를 웹뷰로 띄운다. 키는 빌드할 때 `--dart-define=KAKAO_JS_KEY=...` 로 준다.
/// 키가 없거나 SDK 가 열리지 않으면 [onFail] 로 알려, 호출한 쪽이 다른 지도로 바꾼다.
const kakaoJsKey = String.fromEnvironment('KAKAO_JS_KEY');

class KakaoMap extends StatefulWidget {
  const KakaoMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.level,
    required this.onTap,
    required this.onFail,
  });
  final double lat;
  final double lng;
  final int level; // 카카오 지도 레벨(작을수록 확대)
  final VoidCallback onTap;
  final VoidCallback onFail;

  @override
  State<KakaoMap> createState() => _KakaoMapState();
}

class _KakaoMapState extends State<KakaoMap> {
  late final WebViewController _c;

  String get _html =>
      '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<style>html,body,#m{margin:0;width:100%;height:100%;overflow:hidden}</style></head>
<body><div id="m"></div>
<script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=$kakaoJsKey&autoload=false"
  onerror="Status.postMessage('fail')"></script>
<script>
if (typeof kakao === 'undefined') { Status.postMessage('fail'); }
else kakao.maps.load(function () {
  var p = new kakao.maps.LatLng(${widget.lat}, ${widget.lng});
  var map = new kakao.maps.Map(document.getElementById('m'), {center: p, level: ${widget.level}, draggable: false, scrollwheel: false, disableDoubleClickZoom: true});
  new kakao.maps.Marker({position: p, map: map});
  kakao.maps.event.addListener(map, 'click', function () { Tap.postMessage('tap'); });
  Status.postMessage('ok');
});
setTimeout(function () { if (typeof kakao === 'undefined' || !kakao.maps || !kakao.maps.Map) Status.postMessage('fail'); }, 8000);
</script></body></html>''';

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Tap', onMessageReceived: (_) => widget.onTap())
      ..addJavaScriptChannel(
        'Status',
        onMessageReceived: (m) {
          if (m.message == 'fail') widget.onFail();
        },
      )
      ..loadHtmlString(_html, baseUrl: 'http://localhost');
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _c);
}
