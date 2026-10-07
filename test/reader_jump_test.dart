import 'package:flutter_test/flutter_test.dart';
import 'package:amud/features/siddur/reader_jump.dart';

void main() {
  test('Shomer Yisrael is not Sefirat HaOmer', () {
    expect(keyPointFor('Shomer Yisrael'), isNull);
    expect(keyPointFor('Sefirat HaOmer')?.$1, 'Sefirat HaOmer');
    expect(keyPointFor('Counting of the Omer')?.$1, 'Sefirat HaOmer');
    expect(keyPointFor('Weekday Maariv/Sefirat HaOmer')?.$1, 'Sefirat HaOmer');
  });
}
