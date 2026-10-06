import 'dart:convert';

import 'package:amud/core/settings.dart';
import 'package:amud/features/integrations/prayer_links.dart';
import 'package:amud/features/integrations/seasonal_windows.dart';
import 'package:amud/features/integrations/widget_snapshot.dart';
import 'package:amud/features/js_cards/card_gallery_screen.dart';
import 'package:amud/features/personal_dates/personal_dates.dart';
import 'package:amud/features/zmanim/zman_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(initHebcal);

  test('web, app and legacy hash links route to the same prayer', () {
    expect(
      routeFromLink(
        Uri.parse('https://amud.page/app/#/siddur/ashkenaz/mincha'),
      ),
      '/siddur/ashkenaz/mincha',
    );
    expect(
      routeFromLink(Uri.parse('https://amud.page/app/siddur/ashkenaz/mincha')),
      '/siddur/ashkenaz/mincha',
    );
    expect(routeFromLink(Uri.parse('amud://pray/derech')), '/pray/derech');
    expect(routeFromLink(sharePrayerLink('tefillat-haderech')), '/pray/derech');
    expect(
      routeFromLink(
        Uri.parse(
          'https://amud.page/app/read/Siddur%20Ashkenaz?node=Weekday%2FMincha',
        ),
      ),
      '/read/Siddur%20Ashkenaz?node=Weekday%2FMincha',
    );
  });

  test('voice features resolve to existing screens', () {
    expect(
      routeFromLink(Uri.parse('amud://voice/shacharis')),
      '/pray/shacharit',
    );
    expect(routeFromLink(Uri.parse('amud://voice/zmanim')), '/zmanim');
    expect(routeFromLink(Uri.parse('amud://voice/omer')), '/pray/omer');
  });

  test('device preferences survive storage with safe defaults', () {
    final defaults = AppSettings.fromJson({});
    expect(defaults.keepReaderAwake, isTrue);
    expect(defaults.fullscreenReader, isFalse);
    final enabled = defaults.copyWith(
      keepReaderAwake: false,
      fullscreenReader: true,
      travelPrompts: true,
      desktopTray: true,
      omerBadge: true,
      levanaReminder: true,
      hachamaReminder: true,
    );
    expect(AppSettings.fromJson(enabled.toJson()).toJson(), enabled.toJson());
  });

  test('external domains and unsafe paths do not enter the app router', () {
    for (final value in [
      'https://evil.example/app/pray/mincha',
      'https://amud.page.evil/app/pray/mincha',
      'https://user@amud.page/app/pray/mincha',
      'amud://pray/../../settings',
      'file:///pray/mincha',
      'amud://settings',
    ]) {
      expect(routeFromLink(Uri.parse(value)), isNull, reason: value);
    }
  });

  test(
    'device effects recognize all readers and exclude settings and the library',
    () {
      for (final path in [
        '/pray/mincha',
        '/read/Siddur',
        '/siddur/book/Siddur/read',
        '/siddur/ashkenaz/mincha',
        '/torah/halacha/work/read',
        '/torah/tehillim/read',
      ]) {
        expect(isReaderRoute(path), isTrue);
      }
      for (final path in [
        '/',
        '/siddur',
        '/settings',
        '/settings/fonts',
        '/siddur/book/Siddur',
      ]) {
        expect(isReaderRoute(path), isFalse);
      }
    },
  );

  test('widget dates and Omer advance at sunset while the app is closed', () {
    const settings = AppSettings(location: SavedLocation.newYork);
    final loc = settings.location.toLocation();
    final hd = HDate(15, Months.nisan, 5786);
    final sunset = Zmanim(loc, hd.plainDate(), false).sunset()!;
    final timeline = buildWidgetTimeline(
      settings,
      ZmanResolver(const []),
      sunset.subtract(const Duration(minutes: 1)),
    );
    final before = activeWidgetEntry(
      timeline,
      sunset.subtract(const Duration(seconds: 1)),
    )!;
    final after = activeWidgetEntry(
      timeline,
      sunset.add(const Duration(seconds: 1)),
    )!;
    expect(before['hebrewDate'], hd.renderGematriya(true));
    expect(before['omer'], 0);
    expect(after['hebrewDate'], hd.next().renderGematriya(true));
    expect(after['omer'], 1);
    expect(
      after['nextZmanAt'] as num,
      greaterThan(sunset.millisecondsSinceEpoch),
    );
    expect(() => jsonEncode(timeline), returnsNormally);
  });

  test(
    'late-night widgets find tomorrow’s dawn and expire instead of showing stale data',
    () {
      const settings = AppSettings();
      final zone = settings.location.toLocation().tzLocation;
      final now = tz.TZDateTime(zone, 2026, 10, 1, 23, 59);
      final timeline = buildWidgetTimeline(
        settings,
        ZmanResolver(const []),
        now,
      );
      final active = activeWidgetEntry(timeline, now)!;
      expect(active['nextZmanAt'], isNotNull);
      expect(
        (active['nextZmanAt'] as num).toInt(),
        greaterThan(now.millisecondsSinceEpoch),
      );
      expect(
        activeWidgetEntry(
          timeline,
          DateTime.fromMillisecondsSinceEpoch(timeline['validUntil'] as int),
        ),
        isNull,
      );
      expect((timeline['entries'] as List).length, greaterThan(20));
    },
  );

  test('Hebrew anniversary rules handle Adar and variable month lengths', () {
    final birthday = PersonalDate(
      id: '1',
      name: 'Birthday',
      kind: PersonalDateKind.birthday,
      date: HDate(20, Months.adarII, 5784),
    );
    expect(birthday.occurrence(5785)!.getMonth(), Months.adarI);
    final yahrzeit = PersonalDate(
      id: '2',
      name: 'Yahrzeit',
      kind: PersonalDateKind.yahrzeit,
      date: HDate(30, Months.cheshvan, 5783),
    );
    expect(yahrzeit.occurrence(5783), isNull);
    expect(
      yahrzeit.occurrence(5786)!.abs(),
      getYahrzeit(5786, yahrzeit.date)!.abs(),
    );
    expect(
      PersonalDate.fromJson(birthday.toJson()).toJson(),
      birthday.toJson(),
    );
  });

  test('bar mitzvah parsha starts at thirteen and skips holiday readings', () {
    final date = PersonalDate(
      id: 'bar',
      name: 'Bar',
      kind: PersonalDateKind.barMitzvah,
      date: HDate(15, Months.nisan, 5773),
    );
    expect(date.occurrence(5785), isNull);
    final next = date.nextOccurrence(HDate(1, Months.tishrei, 5786))!;
    expect(next.getFullYear(), 5786);
    expect(date.parsha(next, false), isNotNull);
  });

  test(
    'personal reminders use the saved timezone and keep their destination',
    () {
      const settings = AppSettings(location: SavedLocation.jerusalem);
      final event = PersonalDate(
        id: 'birth',
        name: 'Birthday',
        kind: PersonalDateKind.birthday,
        date: HDate(12, Months.tishrei, 5770),
        eveningBefore: false,
      );
      final day = event.occurrence(5787)!.plainDate();
      final now = tz.TZDateTime(
        settings.location.toLocation().tzLocation,
        day.year,
        day.month,
        day.day,
        8,
      );
      final plan = planPersonalDates([event], settings, now, days: 2);
      expect(plan, hasLength(1));
      expect(plan.single.route, '/personal-dates');
      final fire = tz.TZDateTime.from(
        plan.single.fireAt,
        settings.location.toLocation().tzLocation,
      );
      expect(fire.hour, 9);
      expect(
        plan.single.id,
        planPersonalDates([event], settings, now, days: 2).single.id,
      );
    },
  );

  test('tonight’s Levana reminder survives scheduling after sunset', () {
    const settings = AppSettings(levanaReminder: true);
    final hd = HDate(8, Months.cheshvan, 5787);
    final z = Zmanim(settings.location.toLocation(), hd.plainDate(), false);
    final now = z.sunset()!.add(const Duration(minutes: 1)).toUtc();
    final fire = z.tzeit(8.5)!;
    expect(now.isBefore(fire), isTrue);
    final plan = planSeasonalReminders(settings, now, days: 1);
    expect(plan.single.fireAt, fire);
    expect(
      planSeasonalReminders(
        settings,
        fire.add(const Duration(seconds: 1)),
        days: 1,
      ),
      isEmpty,
    );
  });

  test(
    'Kiddush Levana reminders only fall inside the chosen instant window',
    () {
      const settings = AppSettings(levanaReminder: true);
      final hd = HDate(8, Months.cheshvan, 5787);
      final now = hd.greg().toUtc();
      final notifications = planSeasonalReminders(settings, now);
      expect(notifications, isNotEmpty);
      for (final notification in notifications) {
        final date = Zmanim.makeSunsetAwareHDate(
          settings.location.toLocation(),
          notification.fireAt,
          false,
        );
        final window = levanaWindow(date, settings.minhagim.kiddushLevana3Days);
        expect(notification.fireAt.isBefore(window.start), isFalse);
        expect(notification.fireAt.isBefore(window.end), isTrue);
        expect(notification.route, '/pray/kiddushLevana');
      }
      expect(planSeasonalReminders(const AppSettings(), now), isEmpty);
    },
  );

  test(
    'community galleries reject unsupported schemas and oversize scripts',
    () {
      expect(
        () => parseCardGallery('{"version":2,"cards":[]}'),
        throwsFormatException,
      );
      expect(
        () => parseCardGallery(
          jsonEncode({
            'version': 1,
            'cards': [
              {
                'id': 'test',
                'title': 'Test',
                'description': 'Test',
                'author': 'Test',
                'script': 'x' * 64001,
              },
            ],
          }),
        ),
        throwsFormatException,
      );
    },
  );
}
