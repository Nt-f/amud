import 'package:amud/features/siddur/reading_marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verse numbers in Hallel are marked, words are not', () {
    const psalm = 'א הַלְלוּ יָהּ הַלְלוּ עַבְדֵי יְהוָה הַלְלוּ אֶת שֵׁם יְהוָה. ב יְהִי שֵׁם יְהוָה מְבֹרָךְ';
    final out = verseNumbers(psalm);
    expect(out, startsWith('<sup class="verse">א</sup> הַלְלוּ'));
    expect(out, contains('. <sup class="verse">ב</sup> יְהִי'));
    expect('<sup'.allMatches(out).length, 2);
  });

  test('ordinary prayer text is untouched', () {
    const text = 'בָּרוּךְ אַתָּה יְהוָה אֱלֹהֵינוּ מֶלֶךְ הָעוֹלָם. אֲשֶׁר קִדְּשָׁנוּ';
    expect(verseNumbers(text), text);
  });

  test('a verse number run into its verse is marked and spaced', () {
    expect(verseNumbers('יא אֲנִי כֹּזֵב. יבמָה אָשִׁיב'), 'יא אֲנִי כֹּזֵב. <sup class="verse">יב</sup> מָה אָשִׁיב'.replaceFirst('יא', '<sup class="verse">יא</sup>'));
    // A pointed word after a full stop is left alone.
    expect(verseNumbers('כֹּזֵב. מָה אָשִׁיב'), 'כֹּזֵב. מָה אָשִׁיב');
    // Without the verse before it, it is just a word.
    expect(verseNumbers('כֹּזֵב. יבמָה אָשִׁיב'), 'כֹּזֵב. יבמָה אָשִׁיב');
  });

  test('a word whose first letter has no vowel of its own is not a verse number', () {
    // Ashrei: ט, י and ס begin their verses; each is a letter of the word.
    for (final w in ['טוֹב יְהוָה לַכֹּל', 'יוֹדוּךָ יְהוָה כָּל', 'סוֹמֵךְ יְהוָה לְכָל', 'קוֹל יְהוָה', 'כּוֹס יְשׁוּעוֹת']) {
      final text = 'וּגְדָל חָסֶד. $w';
      expect(verseNumbers(text), text, reason: w);
    }
    // Unvowelled first letters, as this corpus often prints them.
    for (final w in ['סומֵךְ ה לְכָל', 'נוטֶה שָׁמַיִם', 'עלַת תָּמִיד', 'שעִירֵי רָאשֵׁי']) {
      final text = 'וּגְדָל חָסֶד. $w';
      expect(verseNumbers(text), text, reason: w);
    }
    // Glued numerals chain: 12, then 13, each the verse after the last.
    final chain = verseNumbers('יא אֲנִי כֹּזֵב. יבמָה אָשִׁיב. יגכּוֹס יְשׁוּעוֹת');
    expect('<sup'.allMatches(chain).length, 3);
  });
}
