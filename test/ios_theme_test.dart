import 'package:amud/core/settings.dart';
import 'package:amud/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("on iOS the interface is in San Francisco at Apple's sizes, whatever the reader's Latin font", (t) async {
    final theme = buildTheme(const AppSettings(latinFont: 'FrankRuhlLibre'), Brightness.light);
    final body = theme.textTheme.bodyLarge!;
    expect(body.fontFamily, 'CupertinoSystemText');
    expect(body.fontSize, 17);
    expect(body.letterSpacing, closeTo(-0.43, 0.001));
    expect(theme.textTheme.headlineLarge!.fontFamily, 'CupertinoSystemDisplay');
    expect(theme.appBarTheme.titleTextStyle!.fontSize, 17);
    expect(theme.appBarTheme.titleTextStyle!.fontWeight, FontWeight.w600);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('elsewhere the Latin font the reader chose sets the interface too', (t) async {
    final theme = buildTheme(const AppSettings(latinFont: 'FrankRuhlLibre'), Brightness.light);
    expect(theme.textTheme.bodyLarge!.fontFamily, 'FrankRuhlLibre');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test("San Francisco's tracking follows Apple's table between its sizes", () {
    expect(appleTracking(17), closeTo(-0.43, 0.001));
    expect(appleTracking(12), 0);
    expect(appleTracking(18.5), closeTo(-0.44, 0.001));
    expect(appleTracking(100), 0.25);
  });
}
