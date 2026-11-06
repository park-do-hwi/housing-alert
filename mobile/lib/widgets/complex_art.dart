import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 유형별 색(ChatGPT 3차 일러스트 팔레트).
/// 순서: 하늘 위, 하늘 아래, 동 3색, 동 옆면 3색, 창문, 줄기, 잎, 땅
class _Palette {
  const _Palette(this.skyTop, this.skyBottom, this.towers, this.sides, this.window, this.trunk, this.leaf, this.ground);
  final Color skyTop, skyBottom, window, trunk, leaf, ground;
  final List<Color> towers, sides;
}

const _sale = _Palette(Color(0xFFDCEEFF), Color(0xFF9EC8F5), [Color(0xFF6B9FD9), Color(0xFF407FC5), Color(0xFF82B2E5)],
    [Color(0xFF4F86C4), Color(0xFF2D66A8), Color(0xFF6098D1)], Color(0xFFEAF5FF), Color(0xFF497B73), Color(0xFF5BAF91), Color(0xFF245A91));
const _lottery = _Palette(Color(0xFFF0E5FF), Color(0xFFC9B0F0), [Color(0xFFA68AD5), Color(0xFF8162BE), Color(0xFFB79AE3)],
    [Color(0xFF8768C0), Color(0xFF65479F), Color(0xFF9775CC)], Color(0xFFF8F1FF), Color(0xFF657C85), Color(0xFF8DB8A7), Color(0xFF59428A));
const _jeonse = _Palette(Color(0xFFDDF8EF), Color(0xFF9DDBC6), [Color(0xFF66B7A1), Color(0xFF32957C), Color(0xFF86CDB7)],
    [Color(0xFF469780), Color(0xFF24745F), Color(0xFF5DAE94)], Color(0xFFE9FFF7), Color(0xFF376C59), Color(0xFF4DAB73), Color(0xFF216B59));
const _rental = _Palette(Color(0xFFFFF0DC), Color(0xFFF4CC9C), [Color(0xFFDFA76F), Color(0xFFC7864D), Color(0xFFEDBD89)],
    [Color(0xFFBD8555), Color(0xFFA86734), Color(0xFFD69E66)], Color(0xFFFFF5E8), Color(0xFF846B50), Color(0xFF8CB28B), Color(0xFF966039));

_Palette _paletteFor(List<String> tags) {
  if (tags.contains('무순위')) return _lottery;
  if (tags.contains('장기전세')) return _jeonse;
  if (tags.contains('임대')) return _rental;
  return _sale;
}

/// 공고마다 다르게 그려지는 아파트 단지 일러스트. 같은 id 는 항상 같은 모양이다.
/// 사진이 없을 때 목록·상세에서 쓴다.
class ComplexArt extends StatelessWidget {
  const ComplexArt({super.key, required this.id, required this.tags});
  final String id;
  final List<String> tags;

  /// 문자열 → 안정적인 정수(Dart 의 hashCode 는 실행마다 다를 수 있어 직접 계산)
  static int seedOf(String s) {
    var h = 2166136261;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 16777619) & 0x7fffffff;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ComplexPainter(seedOf(id), _paletteFor(tags)), size: Size.infinite);
}

class _ComplexPainter extends CustomPainter {
  _ComplexPainter(this.seed, this.p);
  final int seed;
  final _Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final s = math.min(size.width, size.height) / 72; // 72×72 기준 좌표를 비율로 키운다
    canvas.save();
    // 넓은 영역(히어로)에서는 정사각형을 가운데에 두고 양옆을 하늘색으로 채운다.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(p.skyTop, Colors.white, r.nextDouble() * 0.3)!, p.skyBottom],
          ).createShader(Offset.zero & size));
    canvas.translate((size.width - 72 * s) / 2, (size.height - 72 * s) / 2);
    canvas.scale(s);

    final fill = Paint();
    Rect rr(double x, double y, double w, double h) => Rect.fromLTWH(x, y, w, h);

    // 해 또는 구름
    if (r.nextBool()) {
      fill.color = p.window.withValues(alpha: 0.55);
      canvas.drawCircle(Offset(10 + r.nextDouble() * 52, 8 + r.nextDouble() * 6), 4 + r.nextDouble() * 2, fill);
    }

    // 동
    final n = 2 + r.nextInt(3); // 2~4동
    final widths = [for (var i = 0; i < n; i++) 11 + r.nextDouble() * 8];
    final gap = 2.0;
    final total = widths.fold<double>(0, (a, b) => a + b) + gap * (n - 1);
    var x = (72 - total) / 2;
    const ground = 58.0;
    for (var i = 0; i < n; i++) {
      final w = widths[i];
      final h = 22 + r.nextDouble() * 30;
      final y = ground - h;
      final k = r.nextInt(3);
      fill.color = p.towers[k];
      canvas.drawRRect(RRect.fromRectAndRadius(rr(x, y, w, h), const Radius.circular(1.2)), fill);
      fill.color = p.sides[k];
      canvas.drawRect(rr(x + w * 0.78, y, w * 0.22, h), fill);
      if (r.nextInt(3) == 0) {
        // 옥탑
        canvas.drawRect(rr(x + w * 0.3, y - 3, w * 0.4, 3), fill..color = p.sides[k]);
      }
      // 창문
      fill.color = p.window;
      final cols = ((w * 0.72 - 2) / 4.6).floor().clamp(1, 4);
      final rows = ((h - 6) / 7).floor().clamp(1, 7);
      final cw = (w * 0.72 - 2) / cols;
      for (var cx = 0; cx < cols; cx++) {
        for (var cy = 0; cy < rows; cy++) {
          if (r.nextInt(10) == 0) continue; // 가끔 꺼진 창
          canvas.drawRect(rr(x + 1.5 + cx * cw, y + 4 + cy * 7, cw - 1.6, 3.8), fill);
        }
      }
      x += w + gap;
    }

    // 나무
    final trees = 2 + r.nextInt(3);
    for (var i = 0; i < trees; i++) {
      final tx = 3 + r.nextDouble() * 66;
      final tr = 3 + r.nextDouble() * 2.5;
      canvas.drawRect(rr(tx - 0.8, ground - tr - 1, 1.6, tr + 2), fill..color = p.trunk);
      canvas.drawCircle(Offset(tx, ground - tr - 2), tr, fill..color = p.leaf);
    }

    // 땅
    canvas.drawRect(rr(-200, ground, 472, 200), fill..color = p.ground);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ComplexPainter old) => old.seed != seed || old.p != p;
}
