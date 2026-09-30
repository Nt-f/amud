import 'package:flutter/widgets.dart';
import 'package:flutter_siddur/core/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ashkenazi spelling', () {
    expect(ashkenaziSpelling('Sukkot IV (CH\'\'M)'), 'Sukkos IV (CH\'\'M)');
    expect(ashkenaziSpelling('Kabbalat Shabbat'), 'Kabbalas Shabbos');
    expect(ashkenaziSpelling('Weekday Shacharit'), 'Weekday Shacharis');
    expect(ashkenaziSpelling('Birkat Hamazon'), 'Birchas Hamazon');
    expect(ashkenaziSpelling('Shabbat Shuva, Shemini Atzeret'), 'Shabbos Shuva, Shemini Atzeres');
    expect(ashkenaziSpelling('SHAVUOT'), 'SHAVUOS');
    // Doesn't touch words that merely contain a term.
    expect(ashkenaziSpelling('Alphabet and betting'), 'Alphabet and betting');
  });

  test('translations fall back to English', () {
    const he = AppText(lang: UiLanguage.he, ashkenazi: false, child: SizedBox());
    const yi = AppText(lang: UiLanguage.yi, ashkenazi: true, child: SizedBox());
    expect(he.tr('Settings'), 'הגדרות');
    expect(yi.tr('Settings'), 'איינשטעלונגען');
    expect(yi.tr('{n} minutes', {'n': 18}), '18 מינוט');
    expect(yi.tr('Untranslated Shabbat string'), 'Untranslated Shabbos string');
    expect(yi.hebcalLocale, 'he-x-NoNikud');
    expect(const AppText(lang: UiLanguage.en, ashkenazi: true, child: SizedBox()).hebcalLocale, 'ashkenazi');
  });
}
