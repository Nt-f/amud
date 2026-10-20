import 'dart:convert';

import 'package:amud/core/l10n.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/features/integrations/assistant.dart';
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

  test('assistant requests: every prayer, topic ids and the user\'s own words', () {
    for (final p in ['musaf', 'bedtime', 'hallel', 'havdalah', 'kiddushLevana', 'birkatHaChama']) {
      expect(routeFromLink(Uri.parse('amud://voice/$p')), '/pray/$p');
    }
    expect(routeFromLink(Uri.parse('amud://voice/kiddushlevana')), '/pray/kiddushLevana');
    expect(routeFromLink(Uri.parse('amud://voice/sunset')), '/ask?topic=sunset');
    expect(routeFromLink(Uri.parse('amud://voice/nextZman')), '/ask?topic=nextZman');
    expect(routeFromLink(Uri.parse('amud://voice/ask?q=when%20is%20sunrise')), '/ask?q=when+is+sunrise');
    expect(routeFromLink(Uri.parse('amud://voice/ask')), '/ask');
    expect(routeFromLink(Uri.parse('amud://voice/nonsense')), '/siddur');
    expect(routeFromLink(Uri.parse('https://amud.page/app/ask?topic=omer')), '/ask?topic=omer');
  });

  test('spoken words pick a topic in English, Hebrew and Yiddish', () {
    expect(matchAskTopic('when is sunrise tomorrow'), AskTopic.sunrise);
    expect(matchAskTopic('what time is candle lighting'), AskTopic.candles);
    expect(matchAskTopic('מתי השקיעה'), AskTopic.sunset);
    expect(matchAskTopic('פָּרָשַׁת הַשָּׁבוּעַ'), AskTopic.parsha);
    expect(matchAskTopic('כמה ימים בעומר'), AskTopic.omer);
    expect(matchAskTopic('ווען איז ליכט בענטשן'), AskTopic.candles);
    expect(matchAskTopic('the next zman'), AskTopic.nextZman);
    expect(matchAskTopic('what is the Hebrew date'), AskTopic.date);
    expect(matchAskTopic(''), isNull);
    expect(matchAskTopic('pizza recipes'), isNull);
  });

  test('voice features resolve to existing screens', () {
    expect(
      routeFromLink(Uri.parse('amud://voice/shacharis')),
      '/pray/shacharit',
    );
    expect(routeFromLink(Uri.parse('amud://voice/zmanim')), '/zmanim');
    expect(routeFromLink(Uri.parse('amud://voice/omer')), '/pray/omer');
    // The Torah tab: homes, books, the study reader with its query, learning.
    expect(routeFromLink(Uri.parse('https://amud.page/app/torah/gemara')), '/torah/gemara');
    expect(routeFromLink(Uri.parse('https://amud.page/app/torah/mishnah/Mishnah%20Berakhot')), '/torah/mishnah/Mishnah%20Berakhot');
    expect(routeFromLink(Uri.parse('amud://torah/read?b=Berakhot&u=2a&s=3')), '/torah/read?b=Berakhot&u=2a&s=3');
    expect(routeFromLink(Uri.parse('https://amud.page/app/#/torah/read?b=Pirkei%20Avot&u=1')), '/torah/read?b=Pirkei%20Avot&u=1');
    expect(routeFromLink(shareTorahLink('/torah/read?b=Berakhot&u=2a')), '/torah/read?b=Berakhot&u=2a');
    expect(routeFromLink(Uri.parse('amud://learning')), '/learning');
    expect(routeFromLink(Uri.parse('https://amud.page/app/torah/../settings')), isNull);
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
      levanaHeadsUp: true,
      hachamaReminder: true,
      omerReminder: false,
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

  group('Kiddush Levana from the Thursday before a Motzei Shabbat it opens by', () {
    final loc = const AppSettings().location.toLocation();

    // Every window of 5787 (a leap year) and of Tishrei 5788.
    List<({DateTime start, DateTime end})> windows(bool threeDays) {
      var hd = HDate(1, Months.tishrei, 5787);
      final out = [levanaWindow(hd, threeDays)];
      while (hd.getFullYear() == 5787) {
        hd = HDate(1, hd.getMonth(), hd.getFullYear()).addDays(30);
        out.add(levanaWindow(hd, threeDays));
      }
      expect(out, hasLength(14));
      return out;
    }

    // Counted from the window: the Thursday of the week whose Saturday is
    // the first that midnight after it falls in the window.
    PlainDate thursdayBefore(({DateTime start, DateTime end}) w) {
      final opens = PlainDate.fromDateTime(tz.TZDateTime.from(w.start, loc.tzLocation));
      return opens.addDays(4 - opens.dayOfWeek);
    }

    tz.TZDateTime at(PlainDate d, int hour) => tz.TZDateTime(loc.tzLocation, d.year, d.month, d.day, hour);

    test('the card: open, not open yet from that Thursday, or closed', () {
      for (final threeDays in [false, true]) {
        ({LevanaPhase phase, DateTime start, DateTime end}) status(DateTime t) =>
            levanaStatus(t, PlainDate.fromDateTime(tz.TZDateTime.from(t, loc.tzLocation)), loc, useElevation: false, threeDays: threeDays);
        var soon = 0;
        for (final w in windows(threeDays)) {
          expect(status(w.start.add(const Duration(minutes: 1))).phase, LevanaPhase.open);
          expect(status(w.end.subtract(const Duration(minutes: 1))).phase, LevanaPhase.open);
          // Once it closes, the next month's.
          final after = status(w.end.add(const Duration(minutes: 1)));
          expect(after.phase, LevanaPhase.closed);
          expect(after.start.isAfter(w.end), isTrue);
          // Midday on each of the six days before it opens.
          final thursday = thursdayBefore(w);
          final opens = PlainDate.fromDateTime(tz.TZDateTime.from(w.start, loc.tzLocation));
          for (var d = 1; d <= 6; d++) {
            final day = opens.addDays(-d);
            final s = status(at(day, 12));
            expect(s.start, w.start);
            final expected = day.abs >= thursday.abs ? LevanaPhase.soon : LevanaPhase.closed;
            expect(s.phase, expected, reason: '$day, opening ${w.start}');
            if (expected == LevanaPhase.soon) soon++;
          }
        }
        expect(soon, greaterThan(0));
      }
    });

    test('a heads-up on that Thursday morning, only when on and only before it opens', () {
      final first = HDate(1, Months.tishrei, 5787);
      final days = HDate(1, Months.tishrei, 5788).abs() - first.abs();
      final now = at(first.plainDate(), 0);
      for (final threeDays in [false, true]) {
        final settings = AppSettings(
          levanaHeadsUp: true,
          omerReminder: false,
          ashkenaziSpelling: false,
          minhagim: const AppSettings().minhagim.copyWith(kiddushLevana3Days: threeDays),
        );
        final plan = planSeasonalReminders(settings, now, days: days);
        final expected = {
          for (final w in windows(threeDays))
            if (thursdayBefore(w) case final t when at(t, 9).isBefore(w.start) && t.abs >= first.abs() && t.abs < first.abs() + days) t,
        };
        expect(expected, isNotEmpty);
        expect({for (final n in plan) PlainDate.fromDateTime(tz.TZDateTime.from(n.fireAt, loc.tzLocation))}, expected);
        for (final n in plan) {
          final local = tz.TZDateTime.from(n.fireAt, loc.tzLocation);
          expect((local.weekday, local.hour, local.minute), (DateTime.thursday, 9, 0));
          expect(n.title, 'Kiddush Levana');
          expect(n.body, endsWith(', in time for Motzei Shabbat.'));
          expect(n.route, '/pray/kiddushLevana');
        }
        // Off by default.
        expect(planSeasonalReminders(settings.copyWith(levanaHeadsUp: false), now, days: days), isEmpty);
      }
    });
  });

  test('the Omer reminder is on for new installs, and stays off once turned off', () {
    expect(const AppSettings().omerReminder, isTrue);
    expect(AppSettings.fromJson({}).omerReminder, isTrue);
    expect(AppSettings.fromJson(const AppSettings(omerReminder: false).toJson()).omerReminder, isFalse);
  });

  test('Omer reminders: each night of the count at nightfall, not on Shabbat or Yom Tov, nor once counted', () {
    const settings = AppSettings(omerReminder: true, ashkenaziSpelling: false);
    // From the day before the seventh of Pesach, over two weeks of the Omer.
    final start = HDate(20, Months.nisan, 5787);
    // Midnight where the reminders are planned, not where the test runs (CI
    // is UTC: its midnight is the evening before in New York).
    final day = start.plainDate();
    final now = tz.TZDateTime(settings.location.toLocation().tzLocation, day.year, day.month, day.day);
    final plan = planSeasonalReminders(settings, now, days: 14);
    final expected = [
      for (var d = 0; d < 14; d++)
        if (start.addDays(d).next() case final night
            when omerDay(night) > 0 &&
                night.getDay() != 6 &&
                !getHolidaysOnDate(night, settings.location.il).any((e) => e.hasFlag(Flags.chag)))
          omerDay(night),
    ];
    expect(expected, isNot(contains(6)), reason: 'the night of the seventh of Pesach is Yom Tov');
    expect([for (final n in plan) n.body], [for (final d in expected) 'Tonight is day $d of the Omer.']);
    expect(plan.every((n) => n.route == '/pray/omer' && n.title == 'Sefirat HaOmer'), isTrue);
    // In the reader's spelling and language.
    expect(planSeasonalReminders(settings.copyWith(ashkenaziSpelling: true), now, days: 14).first.title, 'Sefiras HaOmer');
    expect(planSeasonalReminders(settings.copyWith(uiLanguage: UiLanguage.he), now, days: 14).first.body, 'הלילה יום ${expected.first} לעומר.');
    // Fires at nightfall.
    final first = start.addDays(List.generate(14, (d) => d).firstWhere((d) => omerDay(start.addDays(d).next()) == expected.first));
    final z = Zmanim(settings.location.toLocation(), first.plainDate(), false);
    expect(plan.first.fireAt, z.tzeit(8.5));
    // Counted tonight: tonight's reminder goes.
    final counted = planSeasonalReminders(settings, now, days: 14, omerCounted: first.next().abs());
    expect(counted.length, plan.length - 1);
    // Outside the Omer, nothing.
    expect(planSeasonalReminders(settings, HDate(8, Months.cheshvan, 5787).greg().toUtc()), isEmpty);
  });

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
