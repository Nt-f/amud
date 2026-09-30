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

  /// The chazzan's repetition (Kedushah, Birkas Kohanim, Modim DeRabbanan).
  final Color chazarah;
  final Color chazarahFill;

  /// Collapsed halachic notes.
  final Color note;

  const SiddurColors({
    required this.todayBar,
    required this.todayFill,
    required this.excluded,
    required this.instruction,
    required this.marker,
    required this.chipToday,
    required this.chazarah,
    required this.chazarahFill,
    required this.note,
  });

  static SiddurColors of(BuildContext context) => Theme.of(context).extension<SiddurColors>()!;

  @override
  SiddurColors copyWith({
    Color? todayBar,
    Color? todayFill,
    Color? excluded,
    Color? instruction,
    Color? marker,
    Color? chipToday,
    Color? chazarah,
    Color? chazarahFill,
    Color? note,
  }) =>
      SiddurColors(
        todayBar: todayBar ?? this.todayBar,
        todayFill: todayFill ?? this.todayFill,
        excluded: excluded ?? this.excluded,
        instruction: instruction ?? this.instruction,
        marker: marker ?? this.marker,
        chipToday: chipToday ?? this.chipToday,
        chazarah: chazarah ?? this.chazarah,
        chazarahFill: chazarahFill ?? this.chazarahFill,
        note: note ?? this.note,
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
      chazarah: Color.lerp(chazarah, other.chazarah, t)!,
      chazarahFill: Color.lerp(chazarahFill, other.chazarahFill, t)!,
      note: Color.lerp(note, other.note, t)!,
    );
  }
}

bool get isCupertinoPlatform =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

ThemeData buildTheme(AppSettings s, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final w = s.warmth.clamp(0.0, 1.0);
  final seeded = ColorScheme.fromSeed(seedColor: Color(s.seedColor), brightness: brightness);
  // Warmth tints the page toward paper (light) or a warm brown (dark).
  Color warm(Color c, Color paper, double max) => Color.lerp(c, paper, w * max)!;
  final surface = dark ? warm(seeded.surface, const Color(0xFF221B12), 0.9) : warm(seeded.surface, const Color(0xFFF4E9D4), 1);
  final scheme = w == 0
      ? seeded
      : seeded.copyWith(
          surface: surface,
          surfaceContainerLowest: warm(seeded.surfaceContainerLowest, dark ? const Color(0xFF1C160E) : const Color(0xFFFBF4E6), dark ? 0.9 : 1),
          surfaceContainerLow: warm(seeded.surfaceContainerLow, dark ? const Color(0xFF2A2218) : const Color(0xFFFAF1DF), dark ? 0.9 : 1),
          surfaceContainer: warm(seeded.surfaceContainer, dark ? const Color(0xFF2F271C) : const Color(0xFFF0E4CC), dark ? 0.9 : 1),
          surfaceContainerHigh: warm(seeded.surfaceContainerHigh, dark ? const Color(0xFF392F22) : const Color(0xFFEBDEC3), dark ? 0.9 : 1),
          surfaceContainerHighest: warm(seeded.surfaceContainerHighest, dark ? const Color(0xFF433828) : const Color(0xFFE5D7BA), dark ? 0.9 : 1),
          onSurface: warm(seeded.onSurface, dark ? const Color(0xFFF1E3CC) : const Color(0xFF3B2F20), 0.8),
        );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: s.latinFont,
    // Native navigation feel on Apple platforms, Material elsewhere.
    // On the web the browser already animates back/forward swipes; a
    // second slide from Flutter on top of it looks doubled and janky, so
    // pages just cross-fade there.
    pageTransitionsTheme: kIsWeb
        ? PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: const _WebFadeTransitionsBuilder()})
        : const PageTransitionsTheme(builders: {
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          }),
    cupertinoOverrideTheme: CupertinoThemeData(primaryColor: scheme.primary, brightness: brightness),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    splashFactory: isCupertinoPlatform ? NoSplash.splashFactory : null,
    // Bottom sheets sit a step above the page, so their headers and
    // segmented controls don't blend into it.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      modalBackgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? scheme.secondaryContainer : scheme.surface),
        foregroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? scheme.onSecondaryContainer : scheme.onSurface),
      ),
    ),
  );
  return base.copyWith(extensions: [
    SiddurColors(
      todayBar: dark ? const Color(0xFFFFC857) : const Color(0xFFE09F1F),
      todayFill: dark ? const Color(0x33FFC857) : const Color(0x22E09F1F),
      excluded: scheme.onSurface.withValues(alpha: 0.38),
      instruction: dark ? const Color(0xFF9FB7E8) : const Color(0xFF5A6F9E),
      marker: dark ? const Color(0xFFFFB0A0) : const Color(0xFFB0413E),
      chipToday: dark ? const Color(0xFF5C4A12) : const Color(0xFFFFE8B3),
      chazarah: dark ? const Color(0xFF7FD1C7) : const Color(0xFF00796B),
      chazarahFill: dark ? const Color(0x2231B3A5) : const Color(0x1400897B),
      note: dark ? const Color(0xFFB8A9D9) : const Color(0xFF6A5A8C),
    ),
  ]);
}

class _WebFadeTransitionsBuilder extends PageTransitionsBuilder {
  const _WebFadeTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  // No reverse fade: a browser swipe-back has already slid the previous
  // page into view, and fading the old page out on top of it flashes it
  // back for a moment. (Flutter never sees that gesture, so
  // popGestureInProgress can't tell it apart from the back button.)
  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child);
}
