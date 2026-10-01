import 'package:amud/core/search.dart';
import 'package:amud/features/search/prayer_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool finds(String query, String en, [String he = '']) =>
      SearchQuery(query).score([en, he, ...prayerNamesFor(en, he).names]) != null;

  test('other names find a prayer', () {
    expect(finds('hataros nedarim', 'Annulment of Vows', 'סדר התרת נדרים'), isTrue);
    expect(finds('grace after meals', 'Birchat HaMazon'), isTrue);
    expect(finds('bentching', 'Post Meal Blessing'), isTrue);
    expect(finds('duchenen', 'Priestly Blessing'), isTrue);
    expect(finds('shir shel yom', 'Song of the Day'), isTrue);
    expect(finds('kiddush levana', 'Blessing of the Moon'), isTrue);
  });

  test("other names don't spread to unrelated prayers", () {
    expect(finds('bentching', 'Asher Yatzar'), isFalse);
    expect(finds('bentching', 'Blessing of the Trees'), isFalse);
    expect(finds('havdala', 'Candle Lighting'), isFalse);
    expect(finds('kiddush', 'Kiddush Levanah'), isTrue);
    expect(prayerNamesFor('Kiddush Levanah', '').key, 'levana');
  });

  test('the same prayer has the same key, a variant of it none', () {
    expect(prayerNamesFor('Birkat HaMazon', '').key, 'birkatHamazon');
    expect(prayerNamesFor('Birchas Hamazon', '').key, 'birkatHamazon');
    expect(prayerNamesFor('Grace after Meals', '').key, 'birkatHamazon');
    expect(prayerNamesFor('Birkat HaMazon; Grace after Meals', '').key, 'birkatHamazon');
    expect(prayerNamesFor('Birkat HaMazon for Circumcision', '').key, isNull);
    expect(prayerNamesFor('Annulment of Vows', 'סדר התרת נדרים').key, 'hatarat');
  });
}
