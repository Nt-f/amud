import 'dart:typed_data';

import 'package:amud/features/voice/voice_command.dart';
import 'package:amud/features/voice/voice_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English, Hebrew and mixed command prefixes preserve target names', () {
    expect(voiceQuery('Please open שְׁמַע ישראל in Amud'), 'שמע ישראל');
    expect(voiceQuery('תפתח לי את עלינו'), 'עלינו');
    expect(voiceQuery('פתח את Shema בשחרית'), 'shema שחרית');
    expect(voiceQuery('Go to קריאת התורה'), 'קריאת התורה');
    expect(voiceQuery('פתחי לי ברכת המזון'), 'ברכת המזון');
  });

  test('services resolve by Hebrew names as well as transliterations', () {
    expect(voicePrayer(voiceQuery('פתח שחרית')), 'shacharit');
    expect(voicePrayer(voiceQuery('Open מעריב')), 'maariv');
    expect(voicePrayer('ברכת המזון'), 'birkat');
    expect(voicePrayer('קריאת שמע על המיטה'), 'bedtime');
    expect(voicePrayer('Shacharis'), 'shacharit');
    expect(voicePrayer('unrecognized prayer'), isNull);
    expect(
      voicePrayer('שמע'),
      isNull,
      reason: 'Shema needs a specific section match',
    );
  });

  test('Kitzur references accept mixed spoken numbers and Hebrew notation', () {
    final mixed = kitzurVoiceReference('open Kitzur סימן three סעיף two')!;
    expect(mixed.chapter, 3);
    expect(mixed.paragraph, 2);
    final hebrew = kitzurVoiceReference(
      'פתח קיצור שולחן ערוך סימן עשרים ושלוש סעיף ארבע',
    )!;
    expect(hebrew.chapter, 23);
    expect(hebrew.paragraph, 4);
    expect(
      kitzurVoiceReference('Kitzur chapter one hundred twenty three')!.chapter,
      123,
    );
    expect(kitzurVoiceReference('קיצור סימן כ״ג סעיף ב')!.chapter, 23);
    expect(kitzurVoiceReference('Kitzur chapter 0'), isNull);
    expect(kitzurVoiceReference('Kitzur chapter 3 seif 0'), isNull);
    expect(kitzurVoiceReference('Kitzur chapter banana'), isNull);
    expect(kitzurVoiceReference('Kitzur 3 seif 2 seif 4'), isNull);
  });

  test('PCM decoding preserves signed little-endian microphone samples', () {
    final samples = voicePcmSamples(
      Uint8List.fromList([0, 128, 0, 0, 255, 127]),
    );
    expect(samples[0], -1);
    expect(samples[1], 0);
    expect(samples[2], closeTo(1, 0.0001));
    expect(voicePcmSamples(Uint8List(0)), isEmpty);
  });
}
