import 'package:amud/features/search/search_sources.dart';
import 'package:amud/features/voice/voice_command.dart';
import 'package:amud/features/voice/voice_matches.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siddur_engine/siddur_engine.dart';

void main() {
  List<PrayerEntry> entries(String book) {
    final root = SchemaNode.parse({
      'enTitle': book,
      'nodes': [
        {
          'enTitle': 'Shacharit',
          'heTitle': 'שחרית',
          'nodes': [
            {'enTitle': 'Shema', 'heTitle': 'שמע'},
            {'enTitle': 'Amidah', 'heTitle': 'עמידה'},
            {'enTitle': 'Aleinu', 'heTitle': 'עלינו'},
          ],
        },
        {
          'enTitle': 'Maariv',
          'heTitle': 'ערבית',
          'nodes': [
            {'enTitle': 'Shema', 'heTitle': 'שמע'},
          ],
        },
      ],
    });
    return [
      for (final node in root.descendants)
        PrayerEntry.of(book, node, node.ancestors),
    ];
  }

  test('Hebrew names and transliterations find the same exact segment', () {
    final index = entries('Siddur Ashkenaz');
    for (final name in ['עלינו', 'Aleinu', 'Alenu']) {
      final matches = voicePrayerMatches(voiceQuery('open $name'), index, [
        'Siddur Ashkenaz',
      ]);
      expect(matches.first.entry.node.id, 'Shacharit/Aleinu');
    }
  });

  test(
    'mixed aliases and Hebrew parent names identify the requested service',
    () {
      final index = entries('Siddur Ashkenaz');
      final matches = voicePrayerMatches(
        voiceQuery('פתח Shemoneh Esrei בשחרית'),
        index,
        ['Siddur Ashkenaz'],
      );
      expect(matches.single.entry.node.id, 'Shacharit/Amidah');
      expect(
        voicePrayerMatches('Shema in ערבית', index, [
          'Siddur Ashkenaz',
        ]).single.entry.node.id,
        'Maariv/Shema',
      );
    },
  );

  test(
    'deduplication prefers chosen siddur and preserves ambiguous services',
    () {
      final index = [
        ...entries('Siddur Sefard'),
        ...entries('Siddur Ashkenaz'),
      ];
      final matches = voicePrayerMatches('שמע', index, [
        'Siddur Ashkenaz',
        'Siddur Sefard',
      ]);
      expect(matches.length, 2);
      expect(matches.map((m) => m.entry.book).toSet(), {'Siddur Ashkenaz'});
      expect(matches.map((m) => m.entry.node.id).toSet(), {
        'Shacharit/Shema',
        'Maariv/Shema',
      });
      expect(voicePrayerMatches('', index, []), isEmpty);
    },
  );
}
