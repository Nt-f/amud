import 'package:hebcal/hebcal.dart';
import 'package:test/test.dart';

void main() {
  test('every Shabbat parsha has seven aliyot in order', () {
    int key(Verse v) => v.chapter * 1000 + v.verse;
    for (final il in [false, true]) {
      for (var year = 5786; year < 5806; year++) {
        final sedra = getSedra(year, il);
        for (var d = HDate(1, Months.tishrei, year).onOrAfter(6); d.getFullYear() == year; d = d.addDays(7)) {
          final p = sedra.lookup(d);
          if (p.chag) continue;
          final r = ParshaReading.of(p.parsha);
          expect(r, isNotNull, reason: '${p.parsha} on $d');
          expect(r!.aliyot, hasLength(7));
          for (var i = 0; i < 7; i++) {
            final (b, e) = r.aliyot[i];
            expect(key(b) <= key(e), isTrue, reason: '${p.parsha} aliyah ${i + 1}');
            if (i > 0) expect(key(b) > key(r.aliyot[i - 1].$2), isTrue, reason: '${p.parsha} aliyah ${i + 1}');
          }
        }
      }
    }
  });

  test('doubled parshiyot and an unknown name', () {
    final r = ParshaReading.of(['Matot', 'Masei'])!;
    expect(r.book, 4);
    expect(r.begin, (chapter: 30, verse: 2));
    expect(r.end, (chapter: 36, verse: 13));
    expect(ParshaReading.of(['Nonesuch']), isNull);
  });
}
