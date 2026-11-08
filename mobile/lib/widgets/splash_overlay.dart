import 'package:flutter/material.dart';

/// 앱을 켤 때 잠깐 보이는 시작 화면. 일정 시간 뒤 부드럽게 사라지고, 사라진 뒤에는 아무것도 그리지 않는다.
/// 이미지는 휴대폰 화면 비율(9:19.5)로 만든 그림이라 화면을 꽉 채우고(cover), 건물이 잘리지 않게 가운데 기준으로 맞춘다.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.child, this.hold = const Duration(milliseconds: 1500)});
  final Widget child;
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
    if (_gone) return widget.child;
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
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
                  dark ? 'assets/splash/splash_dark.jpg' : 'assets/splash/splash_light.jpg',
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
