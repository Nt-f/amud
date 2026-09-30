import 'package:amud/core/html_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opening words: bold on the first line of a prayer, not later ones', () {
    // Metsudah-style lead-in on a later paragraph goes.
    expect(normalizeOpeningBold('<b>הוֹד וְהָדָר</b> לְפָנָיו', opening: false), 'הוֹד וְהָדָר לְפָנָיו');
    // ...but stays where the prayer begins.
    expect(normalizeOpeningBold('<b>הוֹדוּ</b> לַיהוָֹה', opening: true, addIfMissing: true), '<b>הוֹדוּ</b> לַיהוָֹה');
    // A version without it gets one on the opening line only.
    expect(normalizeOpeningBold('מִזְמוֹר שִׁיר', opening: true, addIfMissing: true), '<b>מִזְמוֹר</b> שִׁיר');
    expect(normalizeOpeningBold('מִזְמוֹר שִׁיר', opening: false, addIfMissing: true), 'מִזְמוֹר שִׁיר');
    // Responses bold throughout, and long bold passages, are left as they are.
    expect(normalizeOpeningBold('<b>יְהֵא שְׁמֵהּ רַבָּא</b>', opening: false), '<b>יְהֵא שְׁמֵהּ רַבָּא</b>');
    const long = '<b>קָדוֹשׁ קָדוֹשׁ קָדוֹשׁ יְהֹוָה צְבָאוֹת</b> מְלֹא';
    expect(normalizeOpeningBold(long, opening: false), long);
    // Lines that start with markup or punctuation aren't given a bold word.
    expect(normalizeOpeningBold('<small>בחורף:</small> מַשִּׁיב', opening: true, addIfMissing: true), '<small>בחורף:</small> מַשִּׁיב');
  });
}
