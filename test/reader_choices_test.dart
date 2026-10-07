import 'package:flutter_test/flutter_test.dart';
import 'package:amud/features/siddur/reader_choices.dart';

void main() {
  test('the default answers own table and no occasion', () {
    final a = choiceAnswers(const {});
    expect(a['if_eatingAtOwnTable'], isTrue);
    expect(a['if_guest'], isFalse);
    expect(a['if_festiveMeal'], isFalse);
  });

  test('a picked occasion answers its conditions and only those', () {
    final a = choiceAnswers(const {'occasion': 'bris', 'table': 'guest'});
    expect(a['if_bris'], isTrue);
    expect(a['if_festiveMeal'], isTrue);
    expect(a['if_wedding'], isFalse);
    expect(a['if_guest'], isTrue);
    expect(a['if_eatingAtOwnTable'], isFalse);
  });
}
