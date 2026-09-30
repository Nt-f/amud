import 'package:flutter_siddur/features/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version comparison', () {
    expect(compareVersions('0.2.0', '0.1.0'), 1);
    expect(compareVersions('v1.2.10', '1.2.9'), 1);
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1.0.0+5', '1.0.0'), 0);
    expect(compareVersions('0.9.9', '1.0.0'), -1);
  });
}
