import 'package:amud/features/siddur/reader_compass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bearing to Jerusalem, shortest route and constant bearing', () {
    // New York: northeast along the globe, east on a constant bearing.
    expect(bearingToJerusalem(40.7128, -74.0060), closeTo(54.3, 1));
    expect(bearingToJerusalem(40.7128, -74.0060, rhumbLine: true), closeTo(95.6, 1.5));
    // London is to the west-northwest; Melbourne to the northwest.
    expect(bearingToJerusalem(51.5074, -0.1278), closeTo(113.6, 1));
    expect(bearingToJerusalem(-37.8136, 144.9631), closeTo(286.7, 1));
    // Tel Aviv is just west of Jerusalem, so the compass points east-southeast.
    expect(bearingToJerusalem(32.0853, 34.7818), inInclusiveRange(110, 130));
  });

  test('distance to the Temple Mount', () {
    expect(kmToJerusalem(40.7128, -74.0060), closeTo(9130, 60));
    expect(kmToJerusalem(31.77805, 35.23540), lessThan(0.01));
  });
}
