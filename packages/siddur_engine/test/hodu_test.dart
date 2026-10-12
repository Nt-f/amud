import 'package:siddur_engine/src/hodu.dart';
import 'package:test/test.dart';

String plain(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');

void main() {
  test('the congregation answers the four verses of Hodu', () {
    const psalm = 'א הוֹדוּ לַיהוָה כִּי טוֹב כִּי לְעוֹלָם חַסְדּוֹ. ב יֹאמַר נָא יִשְׂרָאֵל כִּי לְעוֹלָם חַסְדּוֹ. '
        'ג יֹאמְרוּ נָא בֵית אַהֲרֹן כִּי לְעוֹלָם חַסְדּוֹ. ד יֹאמְרוּ נָא יִרְאֵי יְהוָה כִּי לְעוֹלָם חַסְדּוֹ. ה מִן הַמֵּצַר';
    final state = HoduState();
    final pieces = splitHoduResponses(psalm, state)!;
    expect(pieces.where((p) => p.$2).length, 4);
    expect(pieces.map((p) => p.$1).join(), psalm);
    expect(pieces.first.$1, 'א הוֹדוּ לַיהוָה כִּי טוֹב ');
    expect(pieces[1].$1, 'כִּי לְעוֹלָם חַסְדּוֹ.');
    expect(state.done, isTrue);
    // The closing "הודו" of the psalm is said by all.
    expect(splitHoduResponses('הוֹדוּ לַיהוָה כִּי טוֹב כִּי לְעוֹלָם חַסְדּוֹ:', state), isNull);
  });

  test('a verse in bold is split without breaking its tags', () {
    final pieces = splitHoduResponses('<b>יֹֽאמַר־נָא יִשְׂרָאֵל כִּי לְעוֹלָם חַסְדּוֹ:</b>', HoduState())!;
    expect(pieces.map((p) => p.$1).toList(), ['<b>יֹֽאמַר־נָא יִשְׂרָאֵל </b>', '<b>כִּי לְעוֹלָם חַסְדּוֹ:</b>']);
    expect(pieces.map((p) => p.$2).toList(), [false, true]);
  });

  test('other text is left alone', () {
    expect(splitHoduResponses('כִּי לְעוֹלָם חַסְדּוֹ', HoduState()), isNull);
  });
}
