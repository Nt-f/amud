import 'package:amud/core/hebrew_text.dart';
import 'package:amud/features/tehillim/tehillim_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hebcal/hebcal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('monthly cycle', () {
    expect(monthlyPortion(HDate(1, Months.tishrei, 5787)).rangeLabel, '1–9');
    expect(monthlyPortion(HDate(25, Months.tishrei, 5787)).passages.single.toString(), '119:1-96');
    expect(monthlyPortion(HDate(26, Months.tishrei, 5787)).passages.single.toString(), '119:97-');
    // Iyar always has 29 days: the 29th finishes the sefer.
    final hd = HDate(29, Months.iyyar, 5787);
    expect(hd.daysInMonth(), 29);
    expect(monthlyPortion(hd).rangeLabel, '140–150');
    expect(monthlyPortion(HDate(29, Months.tishrei, 5787)).rangeLabel, '140–144');
  });

  test('weekly cycle and shir shel yom', () {
    expect(weeklyPortion(0).rangeLabel, '1–29');
    expect(weeklyPortion(6).rangeLabel, '120–150');
    expect(shirShelYom(6).passages.single.chapter, 92);
    expect(shirShelYom(3).passages.map((p) => p.toString()), ['94', '95:1-3']);
  });

  test('Psalm 119 by name', () {
    final p = nameStanzas('משה');
    expect(p.passages.map((x) => '${x.from}-${x.to}'), ['97-104', '161-168', '33-40']);
    expect(nameStanzas('אברהם', neshamah: true).passages.map(stanzaLetter).join(), 'אברהמנשמה');
  });

  test('ketiv and qere', () {
    const v = 'לְמַ֥עַן <span class="mam-kq"><span class="mam-kq-k">(הושר)</span> <span class="mam-kq-q">[הַיְשַׁ֖ר]</span></span> לְפָנַ֣י';
    expect(prepareVerse(v), 'לְמַ֥עַן הַיְשַׁ֖ר לְפָנַ֣י');
    expect(prepareVerse(v, ketiv: true), 'לְמַ֥עַן הַיְשַׁ֖ר <small>(הושר)</small> לְפָנַ֣י');
    expect(prepareVerse('תֹּאבֵֽד׃&nbsp;<span class="mam-spi-pe">{פ}</span><br>'), 'תֹּאבֵֽד׃');
  });

  test('marks and numerals', () {
    expect(stripTeamim('שְׁמַ֖ע יִשְׂרָאֵ֑ל'), 'שְׁמַע יִשְׂרָאֵל');
    expect(stripNikud(stripTeamim('שְׁמַ֖ע')), 'שמע');
    expect(stripTeamim('יְהֹוָ֥ה&thinsp;<small>׀</small>&thinsp;אֶחָֽד'), 'יְהֹוָה אֶחָֽד');
    expect(hebrewNumeral(1), 'א׳');
    expect(hebrewNumeral(15), 'ט״ו');
    expect(hebrewNumeral(119), 'קי״ט');
    expect(hebrewNumeral(150), 'ק״נ');
  });

  test('bundled text and search', () async {
    final t = await Tehillim.load();
    expect(t.he.length, 150);
    expect(t.verses(119), 176);
    expect(t.he[22][0], contains('רֹ֝עִ֗י'));
    expect(searchTehillim(t, 'רעי').map((h) => (h.chapter, h.verse)), contains((23, 1)));
    expect(searchTehillim(t, 'my shepherd').first.chapter, 23);
  });
}
