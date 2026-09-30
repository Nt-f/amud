import 'package:amud/features/home/today.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';

void main() {
  setUpAll(initHebcal);

  test('a holiday reading on Shabbat gives way to the next parsha', () {
    // Wednesday of Chol HaMoed Sukkot 5787: the coming Shabbat is Shemini
    // Atzeret, so the card shows Bereshit and its date.
    final p = upcomingParsha(HDate(19, Months.tishrei, 5787), false, 'en');
    expect(p.name, 'Parashat Bereshit');
    expect(p.thisWeek, isFalse);
    expect(p.shabbat.plainDate().toString(), '2026-10-10');
    // An ordinary week: this Shabbat's parsha.
    final noach = upcomingParsha(HDate(3, Months.cheshvan, 5787), false, 'en');
    expect(noach.name, 'Parashat Noach');
    expect(noach.thisWeek, isTrue);
  });
}
