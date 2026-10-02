import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../siddur/prayer_catalog.dart';
import '../siddur/siddur_providers.dart';
import 'prayer_links.dart';

/// A compact, resolved Hebrew siddur for the paired watch, from the same text
/// versions and rules as the phone. Entire short prayers are sent, never cut.
Future<List<Map<String, Object?>>> buildWatchPrayers(
  WidgetRef ref,
  HDate date,
) async {
  final settings = ref.read(settingsProvider);
  final prayers = <Map<String, Object?>>[];
  for (final key in ['derech', 'birkat', 'bedtime']) {
    final prayer = await ref.read(sectionRefProvider((key, date.abs())).future);
    if (prayer == null) continue;
    final versions = await ref.read(
      versionSelectionProvider(prayer.book).future,
    );
    final resolver = await ref.read(resolverProvider(prayer.book).future);
    final rows = resolver.resolve(
      prayer.node,
      versions,
      (service) => DayContext.forService(
        date,
        service,
        il: settings.location.il,
        minhagim: settings.minhagim,
      ),
      options: const ResolveOptions(
        excluded: ExcludedDisplay.hide,
        showTranslation: false,
        showHebrew: true,
        showNotes: false,
      ),
    );
    final lines = <String>[];
    for (final row in rows) {
      if (row is SegmentItem && !row.excluded && row.he != null) {
        final text = row.he!.runs
            .where((run) => run.applicability != Applicability.notToday)
            .map((run) => stripHtml(run.html))
            .join();
        if (text.trim().isNotEmpty) {
          lines.add(text.trim());
        }
      }
    }
    final text = lines.join('\n\n');
    if (text.isNotEmpty && text.length <= 32000) {
      prayers.add({
        'key': key,
        'title': prayerShortcuts[key] ?? 'Bedtime Shema',
        'hebrewTitle': prayer.node.he,
        'text': text,
        'book': prayer.book,
      });
    }
  }
  return prayers;
}
