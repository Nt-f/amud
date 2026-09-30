import 'package:amud/core/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int? score(String q, List<String> texts) => SearchQuery(q).score(texts);

  test('ranks starts-with, then word starts, then anywhere', () {
    expect(score('shema', ['Shema before sleep']), 0);
    expect(score('sleep', ['Shema before sleep']), 1);
    expect(score('leep', ['Shema before sleep']), 2);
    expect(score('xyz', ['Shema before sleep']), isNull);
  });

  test('every word must match, in any order', () {
    expect(score('hamazon birkat', ['Birkat HaMazon']), 1);
    expect(score('mazon birkat', ['Birkat HaMazon']), 2);
    expect(score('mazon kiddush', ['Birkat HaMazon']), isNull);
  });

  test('transliterations find each other', () {
    expect(score('shacharis', ['Shacharit']), 3);
    expect(score('birchas hamazon', ['Birkat HaMazon']), 3);
    expect(score('sukkos', ['Sukkot']), 3);
    expect(score('tsitsis', ['Tzitzit']), 3);
    expect(score('shabos', ['Shabbat']), 3);
  });

  test('Hebrew ignores nikud and punctuation', () {
    expect(score('שמע', ['קְרִיאַת שְׁמַע']), 1);
    expect(score('ברכת המזון', ['בִּרְכַּת הַמָּזוֹן']), 0);
    expect(score("ק״ש", ['ק"ש שעל המיטה']), 0);
  });

  test('transliteration guesses stay at word starts', () {
    expect(score('minyan', ['Praying with a minyan']), 1);
    expect(score('minyan', ['Zmanim']), isNull);
    expect(score('minyan', ['18 minutes before sunset']), isNull);
    expect(score('minyan', ['Customs (minhagim)']), isNull);
    expect(score('shema', ['sofZmanShma']), isNull);
  });

  test('tiny queries do not match everything', () {
    expect(score('a', ['Maariv']), 2);
    expect(score('a', ['Shema']), 2);
    expect(score('a', ['Mincha']), 2);
    expect(score('o', ['Mincha']), isNull);
  });

  test('empty query matches, snippet index ignores nikud', () {
    expect(SearchQuery('  ').isEmpty, isTrue);
    // Counted in the text as shown, marks included.
    expect(SearchQuery('שמע').indexIn('קְרִיאַת שְׁמַע'), 9);
    expect(SearchQuery('shema').indexIn('Keriat Shema'), 7);
  });
}
