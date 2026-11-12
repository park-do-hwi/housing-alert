import 'package:flutter/material.dart';

/// 앱을 켤 때 잠깐 보이는 시작 화면. 일정 시간 뒤 부드럽게 사라지고, 사라진 뒤에는 아무것도 그리지 않는다.
/// 이미지는 휴대폰 화면 비율(9:19.5)로 만든 그림이라 화면을 꽉 채우고(cover), 건물이 잘리지 않게 가운데 기준으로 맞춘다.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({
    super.key,
    required this.child,
    required this.dark,
    this.hold = const Duration(milliseconds: 1500),
  });
  final Widget child;

  /// 앱 테마가 어두운지(앱 안의 테마 설정을 따른다. 폰 시스템 설정만 보지 않는다).
  final bool dark;
  final Duration hold;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  bool _visible = true;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.hold, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/splash/splash_light.jpg'), context);
    precacheImage(const AssetImage('assets/splash/splash_dark.jpg'), context);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    // 스플래시가 사라진 뒤에도 Stack 구조를 그대로 둔다. 구조가 바뀌면 child(화면 전체)가 다시 만들어져,
    // 알림으로 막 켜져 상세로 이동해 있던 화면이 공고 정보를 잃고 오류(회색 화면)가 난다.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_gone)
          IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              onEnd: () {
                if (!_visible && mounted) setState(() => _gone = true);
              },
              child: ColoredBox(
                color: dark ? const Color(0xFF030A1F) : const Color(0xFFE4EFFC),
                child: SizedBox.expand(
                  child: Image.asset(
                    dark
                        ? 'assets/splash/splash_dark.jpg'
                        : 'assets/splash/splash_light.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
