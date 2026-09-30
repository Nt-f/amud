import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'settings.dart';

/// Colors used to mark liturgy that applies today / doesn't apply.
@immutable
class SiddurColors extends ThemeExtension<SiddurColors> {
  final Color todayBar;
  final Color todayFill;
  final Color excluded;
  final Color instruction;
  final Color marker;
  final Color chipToday;

  const SiddurColors({
    required this.todayBar,
    required this.todayFill,
    required this.excluded,
    required this.instruction,
    required this.marker,
    required this.chipToday,
  });

  static SiddurColors of(BuildContext context) => Theme.of(context).extension<SiddurColors>()!;

  @override
  SiddurColors copyWith({Color? todayBar, Color? todayFill, Color? excluded, Color? instruction, Color? marker, Color? chipToday}) =>
      SiddurColors(
        todayBar: todayBar ?? this.todayBar,
        todayFill: todayFill ?? this.todayFill,
        excluded: excluded ?? this.excluded,
        instruction: instruction ?? this.instruction,
        marker: marker ?? this.marker,
        chipToday: chipToday ?? this.chipToday,
      );

  @override
  SiddurColors lerp(SiddurColors? other, double t) {
    if (other == null) return this;
    return SiddurColors(
      todayBar: Color.lerp(todayBar, other.todayBar, t)!,
      todayFill: Color.lerp(todayFill, other.todayFill, t)!,
      excluded: Color.lerp(excluded, other.excluded, t)!,
      instruction: Color.lerp(instruction, other.instruction, t)!,
      marker: Color.lerp(marker, other.marker, t)!,
      chipToday: Color.lerp(chipToday, other.chipToday, t)!,
    );
  }
}

bool get isCupertinoPlatform =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

ThemeData buildTheme(AppSettings s, Brightness brightness) {
  final sepia = s.themeMode == AppThemeMode.sepia && brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Color(s.seedColor),
    brightness: brightness,
    surface: sepia ? const Color(0xFFF7EFDF) : null,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: sepia ? const Color(0xFFF7EFDF) : null,
    fontFamily: s.latinFont,
    // Native navigation feel on Apple platforms, Material elsewhere.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
    cupertinoOverrideTheme: CupertinoThemeData(primaryColor: scheme.primary, brightness: brightness),
    cardTheme: CardThemeData(
      elevation: 0,
      color: sepia ? const Color(0xFFFFF8EA) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    splashFactory: isCupertinoPlatform ? NoSplash.splashFactory : null,
  );
  final dark = brightness == Brightness.dark;
  return base.copyWith(extensions: [
    SiddurColors(
      todayBar: dark ? const Color(0xFFFFC857) : const Color(0xFFE09F1F),
      todayFill: dark ? const Color(0x33FFC857) : const Color(0x22E09F1F),
      excluded: scheme.onSurface.withValues(alpha: 0.38),
      instruction: dark ? const Color(0xFF9FB7E8) : const Color(0xFF5A6F9E),
      marker: dark ? const Color(0xFFFFB0A0) : const Color(0xFFB0413E),
      chipToday: dark ? const Color(0xFF5C4A12) : const Color(0xFFFFE8B3),
    ),
  ]);
}
