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
    expect(verseNumbers('כֹּזֵב. יבמָה אָשִׁיב'), 'כֹּזֵב. <sup class="verse">יב</sup> מָה אָשִׁיב');
    // A pointed word after a full stop is left alone.
    expect(verseNumbers('כֹּזֵב. מָה אָשִׁיב'), 'כֹּזֵב. מָה אָשִׁיב');
  });
}
