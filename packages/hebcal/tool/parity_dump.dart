// Emits the same report as the JS reference script (see test/parity_test.dart)
// so the Dart port can be diffed line-by-line against upstream @hebcal/core.
import 'package:hebcal/hebcal.dart';

String _t(DateTime? t, Location loc) {
  if (t == null) return 'X';
  final l = Zmanim(loc, PlainDate(2000, 1, 1), false).toLocal(t);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(l.hour)}:${p(l.minute)}:${p(l.second)}';
}

List<String> parityLines() {
  initHebcal();
  final out = <String>[];
  for (final (name, il) in [('New York', false), ('Jerusalem', true)]) {
    final loc = Location.lookup(name)!;
    final evs = calendar(CalOptions(
      year: 5786, isHebrewYear: true, location: loc, candlelighting: true, sedrot: true,
      omer: true, molad: true, shabbatMevarchim: true, yomKippurKatan: true, behab: true,
      yizkor: true, il: il,
      dailyLearning: {
        'dafYomi': true, 'mishnaYomi': true, 'nachYomi': true, 'yerushalmi': 1, 'rambam1': true,
        'rambam3': true, 'chofetzChaim': true, 'shemiratHaLashon': true, 'psalms': true,
        'pirkeiAvotSummer': true, 'dafWeekly': true, 'kitzurShulchanAruch': true,
        'arukhHaShulchanYomi': true, 'perekYomi': true, 'tanakhYomi': true, '929': true,
        'dirshuAmudYomi': true, 'dirshuDafHalacha': true, 'seferHaMitzvot': true,
      },
    ));
    for (final ev in evs) {
      out.add('CAL $name ${ev.getDate()} | ${ev.render('en')} | ${ev.render('he')}');
    }
  }
  for (final name in ['New York', 'Jerusalem', 'London', 'Hawaii', 'Sydney', 'Helsinki']) {
    final loc = Location.lookup(name)!;
    for (var i = 0; i < 400; i += 7) {
      final d = PlainDate.fromAbs(gregYmdToAbs(2025, 1, 1) + i);
      final z = Zmanim(loc, d, false);
      final vals = [
        z.alotHaShachar(), z.misheyakir(), z.sunrise(), z.sofZmanShma(), z.sofZmanShmaMGA(),
        z.sofZmanTfilla(), z.chatzot(), z.minchaGedola(), z.minchaKetana(), z.plagHaMincha(),
        z.sunset(), z.tzeit(), z.beinHaShmashos(), z.chatzotNight(),
      ].map((t) => _t(t, loc));
      out.add('ZM $name ${d.year}-${d.month}-${d.day} ${vals.join(' ')}');
    }
  }
  for (var i = 0; i < 3000; i += 13) {
    final d = PlainDate.fromAbs(gregYmdToAbs(2020, 1, 1) + i);
    final hd = HDate.fromAbs(d.abs);
    final t = tachanun(hd, false);
    int b(bool x) => x ? 1 : 0;
    out.add('HD ${d.year}-${d.month}-${d.day} $hd ${hd.renderGematriya()} '
        'T${b(t.shacharit)}${b(t.mincha)}${b(t.allCongs)} H${hallel(hd, false).index}');
  }
  for (var y = 5780; y < 5800; y++) {
    for (var m = 1; m <= 13; m++) {
      if (m == 13 && !isLeapYear(y)) continue;
      final mo = Molad(y, m);
      out.add('MOLAD $y $m ${mo.render('en')} ${mo.getInstant().millisecondsSinceEpoch}');
    }
  }
  for (var o = 1; o <= 49; o++) {
    final e = OmerEvent(HDate.today(), o);
    out.add('OMER $o ${e.getTodayIs('he')} | ${e.sefira(OmerLang.he)} | ${e.getTodayIs('en')}');
  }
  return out;
}

void main() => print(parityLines().join('\n'));
