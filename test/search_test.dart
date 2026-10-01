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

  test('transliterations find the Hebrew title', () {
    expect(score('hataros nedarim', ['Annulment of Vows', 'סדר התרת נדרים']), 3);
    expect(score('hatarat nedarim', ['סדר התרת נדרים']), 3);
    expect(score('kriat shema al hamita', ['קריאת שמע על המטה']), 3);
    expect(score('tefilas haderech', ['תפילת הדרך']), 3);
    expect(score('birchas hamazon', ['ברכת המזון']), 3);
    expect(score('shema', ['ברכת המזון']), isNull);
  });

  test('Hebrew spelled with or without vowel letters', () {
    expect(score('תפילת הדרך', ['תפלת הדרך']), 3);
  });

  test('apostrophes are dropped, not word breaks', () {
    expect(score('maariv', ["Ma'ariv for Weekdays"]), 0);
    expect(score('shmoneh esrei', ['Shemoneh Esrei']), 3);
  });

  test('one typo in a longer word', () {
    expect(score('havdallah', ['Havdalah']), anyOf(3, 4));
    expect(score('kidush levana', ['Kiddush Levanah']), anyOf(3, 4));
    expect(score('havdakah', ['Havdalah']), 4);
    expect(score('yizkr', ['Yizkor']), 3, reason: 'only a vowel missing');
  });
}
