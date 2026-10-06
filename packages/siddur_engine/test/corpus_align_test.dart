import 'package:siddur_engine/siddur_engine.dart';
import 'package:test/test.dart';

void main() {
  test('a part carries the alignment the corpus asks for', () {
    final p = CorpusPart.fromJson({'text': 'x', 'kind': 'prayer', 'align': 'center'});
    expect(p.align, 'center');
    expect(CorpusPart.fromJson({'text': 'x'}).align, isNull);
  });
}
