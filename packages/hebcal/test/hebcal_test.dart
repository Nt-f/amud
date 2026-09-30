import 'package:hebcal/hebcal.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initHebcal);

  test('HDate round trip', () {
    final hd = HDate(15, Months.nisan, 5786);
    expect(HDate.fromAbs(hd.abs()), hd);
    expect(hd.greg(), DateTime(2026, 4, 2));
    expect(hd.renderGematriya(true), 'ט״ו ניסן תשפ״ו');
  });

  test('gematriya parse', () {
    expect(gematriyaStrToNum('תשפ״ו'), 786);
    expect(HDate.fromGematriyaString('ט״ו ניסן תשפ״ו'), HDate(15, Months.nisan, 5786));
  });

  test('omer and sunset-aware date', () {
    expect(omerDay(HDate(18, Months.iyyar, 5786)), 33);
    final jlm = Location.lookup('Jerusalem')!;
    final lateEvening = DateTime.utc(2026, 4, 1, 20); // 23:00 IDT on 14 Nisan
    expect(Zmanim.makeSunsetAwareHDate(jlm, lateEvening, false), HDate(15, Months.nisan, 5786));
  });

  test('yahrzeit Adar II falls to Adar in common year', () {
    final y = getYahrzeit(5786, HDate(10, Months.adarII, 5784))!;
    expect(y.getMonth(), Months.adarI);
  });
}
