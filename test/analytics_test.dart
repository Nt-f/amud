import 'package:amud/core/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen names come from route patterns', () {
    expect(Analytics.screenName('/'), 'home');
    expect(Analytics.screenName('/siddur/book/:book/read'), 'siddur_book_read');
    expect(Analytics.screenName('/pray/:section'), 'pray');
    expect(Analytics.screenName('/meein-shalosh'), 'meein_shalosh');
    expect(Analytics.screenName('/torah/:category/:work/read'), 'torah_read');
  });

  test('stays quiet in debug builds and never throws', () {
    expect(analytics.active, isFalse);
    analytics
      ..event('test', {'a': null, 'b': true, 'c': 'x' * 300})
      ..error(StateError('boom'));
    expect(analytics.active, isFalse);
  });
}
