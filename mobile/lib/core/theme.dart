import 'package:flutter/material.dart';

import 'grouping.dart';

/// 간격·모양 토큰 (docs/design_review.md).
class Gap {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 20, section = 24;
  static const double cardRadius = 16, chipRadius = 12, tagRadius = 8;
}

/// 글자색 + 배경색 한 쌍.
class Tone {
  const Tone(this.fg, this.bg);
  final Color fg;
  final Color bg;
}

/// 접수 상태·공고 유형 색. 라이트/다크 각각 따로 정의한다.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.phase, required this.tag});
  final Map<Phase, Tone> phase;
  final Map<String, Tone> tag; // 분양·무순위·장기전세·임대

  Tone phaseTone(Phase p) => phase[p]!;
  Tone tagTone(String t) => tag[t] ?? neutralTag;
  Tone get neutralTag => phase[Phase.undated]!;

  static const light = AppColors(phase: {
    Phase.closingSoon: Tone(Color(0xFFB42318), Color(0xFFFEECEB)),
    Phase.open: Tone(Color(0xFF067647), Color(0xFFDDF7E9)),
    Phase.upcoming: Tone(Color(0xFF1D4ED8), Color(0xFFDBEAFE)),
    Phase.undated: Tone(Color(0xFF475569), Color(0xFFE9EEF5)),
    Phase.closed: Tone(Color(0xFF475569), Color(0xFFE5E7EB)),
  }, tag: {
    '분양': Tone(Color(0xFF1D4ED8), Color(0xFFE8EFFF)),
    '무순위': Tone(Color(0xFF6D28D9), Color(0xFFF0E9FF)),
    '장기전세': Tone(Color(0xFF0F766E), Color(0xFFE0F5F2)),
    '임대': Tone(Color(0xFF92400E), Color(0xFFFDF0D5)),
  });

  static const dark = AppColors(phase: {
    Phase.closingSoon: Tone(Color(0xFFFFB4AB), Color(0xFF552724)),
    Phase.open: Tone(Color(0xFF86EFAC), Color(0xFF16442E)),
    Phase.upcoming: Tone(Color(0xFFA9C7FF), Color(0xFF203A69)),
    Phase.undated: Tone(Color(0xFFCBD5E1), Color(0xFF334155)),
    Phase.closed: Tone(Color(0xFFCBD5E1), Color(0xFF374151)),
  }, tag: {
    '분양': Tone(Color(0xFFBFDBFE), Color(0xFF1E3A5F)),
    '무순위': Tone(Color(0xFFDDD6FE), Color(0xFF3B2B62)),
    '장기전세': Tone(Color(0xFF99F6E4), Color(0xFF164E48)),
    '임대': Tone(Color(0xFFFDE68A), Color(0xFF594015)),
  });

  @override
  AppColors copyWith({Map<Phase, Tone>? phase, Map<String, Tone>? tag}) =>
      AppColors(phase: phase ?? this.phase, tag: tag ?? this.tag);

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsContext on BuildContext {
  /// 앱 테마가 아닌 기본 테마(테스트 등)에서도 밝기에 맞는 색을 돌려준다.
  AppColors get appColors {
    final t = Theme.of(this);
    return t.extension<AppColors>() ?? (t.brightness == Brightness.dark ? AppColors.dark : AppColors.light);
  }
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1D4ED8), brightness: b).copyWith(
    primary: dark ? const Color(0xFF79A7FF) : const Color(0xFF1D4ED8),
    onPrimary: dark ? const Color(0xFF071D42) : Colors.white,
    surface: dark ? const Color(0xFF0F172A) : const Color(0xFFF7F9FC),
    onSurface: dark ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
    onSurfaceVariant: dark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
    surfaceContainerLow: dark ? const Color(0xFF1E293B) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF1E293B) : Colors.white,
    surfaceContainerHighest: dark ? const Color(0xFF263449) : const Color(0xFFEFF4FA),
    outlineVariant: dark ? const Color(0xFF43516B) : const Color(0xFFE2E8F0),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    dividerColor: scheme.outlineVariant,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
          fontSize: 19, height: 26 / 19, fontWeight: FontWeight.w500, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 60,
      labelPadding: EdgeInsets.zero,
      labelTextStyle: WidgetStateProperty.resolveWith((st) {
        final on = st.contains(WidgetState.selected);
        return TextStyle(
            fontSize: 11,
            height: 14 / 11,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? scheme.primary : scheme.onSurfaceVariant);
      }),
      iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
          size: 22, color: st.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: dark ? const Color(0xFF203A69) : const Color(0xFFDBEAFE),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gap.chipRadius)),
    ),
    extensions: [dark ? AppColors.dark : AppColors.light],
  );
}
