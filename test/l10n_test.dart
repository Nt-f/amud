import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:amud/core/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  translationCoverage();
  test('Ashkenazi spelling', () {
    expect(ashkenaziSpelling('Sukkot IV (CH\'\'M)'), 'Sukkos IV (CH\'\'M)');
    expect(ashkenaziSpelling('Kabbalat Shabbat'), 'Kabbalas Shabbos');
    expect(ashkenaziSpelling('Weekday Shacharit'), 'Weekday Shacharis');
    expect(ashkenaziSpelling('Al Naharot · Shir HaMaalot'), 'Al Naharos · Shir HaMaalos');
    expect(ashkenaziSpelling("Say Ya'aleh VeYavo"), "Say Ya'aleh V'Yovo");
    expect(ashkenaziSpelling('the Festival of Matzot; Mashiach'), 'the Festival of Matzos; Moshiach');
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

/// Every interface string in the code has a Hebrew and a Yiddish
/// translation: a missing one silently falls back to English.
void translationCoverage() {
  test('every literal passed to tr() is translated into Hebrew and Yiddish', () {
    final literal = RegExp(r"""\.tr\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")\s*[,)]""");
    final he = const AppText(lang: UiLanguage.he, ashkenazi: false, child: SizedBox());
    final yi = const AppText(lang: UiLanguage.yi, ashkenazi: false, child: SizedBox());
    // Symbols and technical terms that read the same in every language.
    const same = {'×{n}', 'API'};
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('l10n.dart')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        final key = (m.group(1) ?? m.group(2)!).replaceAll("\\'", "'").replaceAll('\\"', '"');
        if (same.contains(key)) continue;
        if (he.tr(key) == key || yi.tr(key) == key) missing.add('${f.path}: $key');
      }
    }
    expect(missing, isEmpty, reason: 'add these to _strings in lib/core/l10n.dart');
  });
}
