import 'package:amud/core/day_start.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/features/zmanim/zman_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(initHebcal);

  test("a day's midnight (chatzot halailah) is tonight's, after its sunset", () {
    final loc = SavedLocation.newYork.toLocation();
    final z = Zmanim(loc, PlainDate(2026, 10, 2), false);
    final midnight = builtInByKey['chatzotNight']!.compute(z)!;
    final tomorrow = Zmanim(loc, PlainDate(2026, 10, 3), false);
    expect(midnight.isAfter(z.sunset()!), isTrue);
    expect(midnight.isBefore(tomorrow.sunrise()!), isTrue);
  });

  group('the day turns over at dawn by the opinion, not midnight', () {
    final loc = SavedLocation.newYork.toLocation();
    DateTime at(int day, int h, int m) => tz.TZDateTime(loc.tzLocation, 2026, 10, day, h, m);
    PlainDate day(DateTime t, ZmanimOpinion o) => dayAt(t, loc, useElevation: false, opinion: o);

    test('after midnight it is still the night before', () {
      expect(day(at(3, 1, 0), ZmanimOpinion.gra), PlainDate(2026, 10, 2));
      expect(day(at(2, 23, 0), ZmanimOpinion.gra), PlainDate(2026, 10, 2));
    });

    test('at dawn the new day begins', () {
      for (final o in ZmanimOpinion.values) {
        final dawn = dawnFor(Zmanim(loc, PlainDate(2026, 10, 3), false), o)!;
        expect(day(dawn.subtract(const Duration(minutes: 1)), o), PlainDate(2026, 10, 2), reason: o.name);
        expect(day(dawn.add(const Duration(minutes: 1)), o), PlainDate(2026, 10, 3), reason: o.name);
      }
    });
  });
}
