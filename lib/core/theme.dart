import 'package:cupertino_native_better/cupertino_native_better.dart' show PlatformVersion;
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

/// iOS 26 and later, where the native controls (tab bar, alerts) are drawn
/// by UIKit in Liquid Glass.
bool get isLiquidGlass => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && PlatformVersion.isIOS26OrLater;

ThemeData buildTheme(AppSettings s, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final w = s.warmth.clamp(0.0, 1.0);
  final seeded = ColorScheme.fromSeed(seedColor: Color(s.seedColor), brightness: brightness);
  // Warmth tints the page toward yellowed paper (light) or a warm brown (dark).
  Color warm(Color c, Color paper, double max) => Color.lerp(c, paper, w * max)!;
  final surface = dark ? warm(seeded.surface, const Color(0xFF261A05), 0.9) : warm(seeded.surface, const Color(0xFFFDE8BD), 1);
  final scheme = w == 0
      ? seeded
      : seeded.copyWith(
          surface: surface,
          surfaceContainerLowest: warm(seeded.surfaceContainerLowest, dark ? const Color(0xFF201503) : const Color(0xFFFFF4DC), dark ? 0.9 : 1),
          surfaceContainerLow: warm(seeded.surfaceContainerLow, dark ? const Color(0xFF2F2109) : const Color(0xFFFFF1D1), dark ? 0.9 : 1),
          surfaceContainer: warm(seeded.surfaceContainer, dark ? const Color(0xFF34260C) : const Color(0xFFFAE3B1), dark ? 0.9 : 1),
          surfaceContainerHigh: warm(seeded.surfaceContainerHigh, dark ? const Color(0xFF3F2D0E) : const Color(0xFFF6DDA5), dark ? 0.9 : 1),
          surfaceContainerHighest: warm(seeded.surfaceContainerHighest, dark ? const Color(0xFF4A360F) : const Color(0xFFF0D599), dark ? 0.9 : 1),
          onSurface: warm(seeded.onSurface, dark ? const Color(0xFFF1E3CC) : const Color(0xFF3B2F20), 0.8),
        );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    // The interface is set in San Francisco on Apple platforms, as native
    // apps are; the Latin font the reader picked is for the texts.
    fontFamily: isCupertinoPlatform ? null : s.latinFont,
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
    // Cupertino rows (settings lists) in the weight of the Material ones.
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: scheme.primary,
      brightness: brightness,
      textTheme: !isCupertinoPlatform ? null : CupertinoTextThemeData(
        primaryColor: scheme.primary,
        textStyle: TextStyle(
            fontFamily: 'CupertinoSystemText', fontSize: 17, letterSpacing: appleTracking(17), fontWeight: _appleRow, color: scheme.onSurface),
      ),
    ),
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
  final apple = isCupertinoPlatform;
  final appleText = apple ? _appleTextTheme(base.textTheme) : null;
  return base.copyWith(
      textTheme: appleText,
      listTileTheme: apple ? ListTileThemeData(titleTextStyle: appleText!.bodyLarge!.copyWith(fontWeight: _appleRow, color: scheme.onSurface)) : null,
      popupMenuTheme: apple ? PopupMenuThemeData(labelTextStyle: WidgetStatePropertyAll(appleText!.bodyLarge!.copyWith(fontWeight: _appleRow, color: scheme.onSurface))) : null,
      // A navigation bar's title: 17pt semibold, centered.
      appBarTheme: apple
          ? base.appBarTheme.copyWith(
              titleTextStyle: _appleStyle(base.textTheme.titleLarge!, 17, FontWeight.w600).copyWith(color: scheme.onSurface))
          : null,
      extensions: [
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

/// Material's roles at the sizes of Apple's text styles (Body 17,
/// Subheadline 15, Footnote 13, Headline 17 semibold...), with San
/// Francisco's own tracking. Material's tracking (+0.5 on body text) spaces
/// San Francisco out until it no longer looks like the system font.
TextTheme _appleTextTheme(TextTheme t) => t.copyWith(
      displayLarge: _appleStyle(t.displayLarge!, 57, FontWeight.w400),
      displayMedium: _appleStyle(t.displayMedium!, 45, FontWeight.w400),
      displaySmall: _appleStyle(t.displaySmall!, 36, FontWeight.w400),
      headlineLarge: _appleStyle(t.headlineLarge!, 34, FontWeight.w700),
      headlineMedium: _appleStyle(t.headlineMedium!, 28, FontWeight.w700),
      headlineSmall: _appleStyle(t.headlineSmall!, 22, FontWeight.w700),
      titleLarge: _appleStyle(t.titleLarge!, 20, FontWeight.w600),
      titleMedium: _appleStyle(t.titleMedium!, 17, FontWeight.w600),
      titleSmall: _appleStyle(t.titleSmall!, 15, FontWeight.w600),
      bodyLarge: _appleStyle(t.bodyLarge!, 17, FontWeight.w400),
      bodyMedium: _appleStyle(t.bodyMedium!, 15, FontWeight.w400),
      bodySmall: _appleStyle(t.bodySmall!, 13, FontWeight.w400),
      labelLarge: _appleStyle(t.labelLarge!, 15, FontWeight.w600),
      labelMedium: _appleStyle(t.labelMedium!, 13, FontWeight.w600),
      labelSmall: _appleStyle(t.labelSmall!, 11, FontWeight.w600),
    );

/// List rows and menus a step above Regular: Flutter sets San Francisco
/// thinner than UIKit does, and Regular read as too light there. Body text
/// stays Regular, since the prayer text inherits its weight.
const _appleRow = FontWeight.w500;

TextStyle _appleStyle(TextStyle s, double size, FontWeight weight) => s.copyWith(
      // The system font in its Text cut below 20pt, Display above, as UIKit
      // switches between them.
      fontFamily: size < 20 ? 'CupertinoSystemText' : 'CupertinoSystemDisplay',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: appleTracking(size),
      // Apple's leading: Body is 17 on 22, Footnote 13 on 18.
      height: switch (size) { <= 11 => 13 / 11, <= 13 => 18 / 13, <= 15 => 20 / 15, <= 17 => 22 / 17, <= 22 => 1.27, _ => 1.21 },
    );

/// San Francisco's tracking at [size] points, from Apple's table for the
/// system font.
double appleTracking(double size) {
  const table = <(double, double)>[
    (11, 0.06), (12, 0), (13, -0.08), (14, -0.15), (15, -0.23), (16, -0.31), (17, -0.43), (20, -0.45),
    (22, -0.26), (24, 0.07), (28, 0.38), (34, 0.40), (40, 0.37), (48, 0.35), (56, 0.30), (64, 0.25),
  ];
  if (size <= table.first.$1) return table.first.$2;
  for (var i = 1; i < table.length; i++) {
    final (s1, t1) = table[i];
    if (size <= s1) {
      final (s0, t0) = table[i - 1];
      return t0 + (t1 - t0) * (size - s0) / (s1 - s0);
    }
  }
  return table.last.$2;
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
