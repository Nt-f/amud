import 'package:amud/features/siddur/reader_compass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the compass points to the Western Wall along the shortest route', () {
    expect(bearingToKotel(40.71427, -74.00597), closeTo(54.1, 0.5)); // New York: northeast, not east
    expect(bearingToKotel(34.0522, -118.2437), closeTo(23.8, 0.5)); // Los Angeles
    expect(bearingToKotel(51.5074, -0.1278), closeTo(113.6, 0.5)); // London
    expect(bearingToKotel(-37.8136, 144.9631), closeTo(286.7, 0.5)); // Melbourne
    expect(bearingToKotel(31.76904, 35.21633), closeTo(63.5, 0.5)); // central Jerusalem
  });
}
