import 'package:flutter/material.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';

/// Shows the actual variables used by a rule, including unknown custom ones.
List<String> conditionFacts(String expression, DayContext day) => [
  for (final key in Condition.parse(expression).identifiers)
    '${DayContext.variableDocs[key] ?? key}: ${switch (day.env[key]) {
      true => 'Yes',
      false => 'No',
      null => 'Unknown',
      final value => value.toString(),
    }}',
];

String resolvedText(ResolvedSegment? segment) => segment == null
    ? ''
    : stripHtml(
        segment.runs
            .where(
              (r) => !r.marker && r.applicability != Applicability.notToday,
            )
            .map((r) => r.html)
            .join(''),
      ).trim();

class PrayerInsight {
  final String explanation;
  final String? source;
  const PrayerInsight(this.explanation, [this.source]);
}

PrayerInsight? insightFor(SegmentItem item) {
  final text = normalizeRubric(
    item.he?.segment.html ?? item.tr?.segment.html ?? '',
  );
  if (text.startsWith('שמע ישראל')) {
    return const PrayerInsight(
      'This verse declares that Hashem is one. It opens the Shema, directing attention to the words that follow.',
      'Deuteronomy 6:4',
    );
  }
  if (text.startsWith('מודה אני')) {
    return const PrayerInsight(
      'A personal expression of gratitude on waking: life has been returned to you, and the day begins with thanks.',
    );
  }
  if (text.contains('יעלה ויבוא')) {
    return const PrayerInsight(
      'This passage asks that we and the Jewish people be remembered favorably, and names the special day being observed.',
    );
  }
  if (text.startsWith('על הנסים') || text.startsWith('ועל הנסים')) {
    return const PrayerInsight(
      'This addition gives thanks for deliverance. Its following paragraph recounts the events of Chanukah or Purim.',
    );
  }
  if (text.startsWith('אשרי יושבי')) {
    return const PrayerInsight(
      'These opening verses introduce a psalm of praise, focusing on those who dwell in Hashem’s house and on the people whose God is Hashem.',
      'Psalms 84:5; 144:15',
    );
  }
  final psalm = RegExp(
    r'psalm\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(item.node.en);
  if (psalm != null) {
    return PrayerInsight(
      'This line is part of a biblical psalm used in prayer. Read the translation alongside it to follow the verse’s meaning.',
      'Psalms ${psalm[1]}',
    );
  }
  final path = item.node.id.toLowerCase();
  if (path.contains('amid') || path.contains('shemoneh')) {
    return const PrayerInsight(
      'The Amidah moves through praise, requests, and thanks. This line belongs to the blessing named above it.',
    );
  }
  if (path.contains('hallel')) {
    return const PrayerInsight(
      'Hallel is a sequence of psalms of praise and thanksgiving. This line is part of that sequence.',
      'Psalms 113–118',
    );
  }
  if (path.contains('mazon') || path.contains('grace after')) {
    return const PrayerInsight(
      'Birkat HaMazon expresses gratitude after a meal, for nourishment and for the blessings of land and community.',
    );
  }
  return null;
}

/// Small offline glossary; only words actually present in the passage appear.
const prayerVocabulary = <String, String>{
  'ברוך': 'Blessed',
  'ברכה': 'Blessing',
  'אתה': 'You',
  'אנחנו': 'We',
  'אלוהינו': 'Our God',
  'אלהינו': 'Our God',
  'אלוהים': 'God',
  'מלך': 'King',
  'העולם': 'The world',
  'שמע': 'Hear; listen',
  'ישראל': 'Israel',
  'אחד': 'One',
  'ואהבת': 'And you shall love',
  'לבבך': 'Your heart',
  'נפשך': 'Your soul; your life',
  'מודה': 'Give thanks; acknowledge',
  'אני': 'I',
  'לפניך': 'Before You',
  'נשמה': 'Soul',
  'נשמתי': 'My soul',
  'רחמים': 'Compassion',
  'שלום': 'Peace',
  'חיים': 'Life',
  'לחיים': 'For life',
  'טוב': 'Good',
  'חסד': 'Kindness',
  'אמת': 'Truth',
  'קדוש': 'Holy',
  'תורה': 'Torah; teaching',
  'תפילה': 'Prayer',
  'תפלתם': 'Their prayer',
  'אבותינו': 'Our ancestors',
  'היום': 'Today; the day',
  'תודה': 'Thanks',
  'אור': 'Light',
  'יהי': 'May it be',
  'רצון': 'Will; favor',
  'זכרנו': 'Remember us',
  'יעלה': 'May it rise',
  'ויבוא': 'And may it come',
  'נסים': 'Miracles',
  'הנסים': 'The miracles',
  'הניסים': 'The miracles',
};

Map<String, String> vocabularyFor(String text) {
  final words = normalizeRubric(
    text,
  ).replaceAll(RegExp(r'[^א-ת ]'), ' ').split(' ').toSet();
  return {
    for (final entry in prayerVocabulary.entries)
      if (words.contains(entry.key)) entry.key: entry.value,
  };
}

Future<void> showLineInsight(
  BuildContext context,
  SegmentItem item,
  DayContext day, {
  String? book,
  String? sectionCondition,
  List<VersionInfo> sources = const [],
}) {
  final insight = insightFor(item);
  final vocabulary = vocabularyFor(item.he?.segment.html ?? '');
  final expressions = <String>{
    if (sectionCondition != null && sectionCondition != 'true')
      sectionCondition,
    if (item.he?.segment.rubric != null) item.he!.segment.rubric!.expression,
    if (item.tr?.segment.rubric != null) item.tr!.segment.rubric!.expression,
    for (final segment in [item.he, item.tr])
      if (segment != null)
        for (final run in segment.segment.runs)
          if (run.rubric != null) run.rubric!.expression,
  };
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Explain this line')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${book == null ? '' : '$book / '}${item.node.en} · ${item.he?.segment.ref ?? item.tr?.segment.ref ?? ''}',
              ),
              const SizedBox(height: 12),
              if ((item.excluded
                      ? item.he?.segment.plain ?? ''
                      : resolvedText(item.he))
                  .isNotEmpty)
                Text(
                  item.excluded
                      ? item.he?.segment.plain ?? ''
                      : resolvedText(item.he),
                  textDirection: TextDirection.rtl,
                ),
              const SizedBox(height: 12),
              Text(
                context.tr('Translation'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                (item.excluded
                            ? item.tr?.segment.plain ?? ''
                            : resolvedText(item.tr))
                        .isEmpty
                    ? context.tr(
                        'No bundled translation is available for this line.',
                      )
                    : item.excluded
                    ? item.tr?.segment.plain ?? ''
                    : resolvedText(item.tr),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr(
                  insight?.explanation ??
                      'No curated explanation is available for this passage yet.',
                ),
              ),
              if (vocabulary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  context.tr('Words in this line'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final word in vocabulary.entries.take(8))
                  Text('${word.key} — ${context.tr(word.value)}'),
              ],
              if (insight?.source != null) ...[
                const SizedBox(height: 8),
                Text('${context.tr('Biblical source')}: ${insight!.source}'),
              ],
              if (expressions.isNotEmpty || item.labelEn != null) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr('Why today?'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (item.labelEn != null) Text(item.labelEn!),
                Text(
                  context.tr(switch (item.applicability) {
                    Applicability.today => 'Included for this date',
                    Applicability.notToday => 'Omitted for this date',
                    Applicability.unknown =>
                      'Depends on circumstances not known to Amud',
                    Applicability.always =>
                      'This line is part of the regular prayer',
                  }),
                ),
                Text(
                  '${day.hdate.render('en')} · ${day.service.name} · ${day.il ? 'Israel' : 'Diaspora'}',
                ),
                for (final expression in expressions) ...[
                  for (final fact in conditionFacts(expression, day))
                    Text(fact),
                ],
                Text(
                  context.tr(
                    'Based on this siddur’s instructions and your selected customs.',
                  ),
                ),
              ],
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr('Text sources'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final source in sources)
                  SelectableText(
                    '${source.versionTitle} · ${source.license}${source.source == null ? '' : '\n${source.source}'}',
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Close')),
        ),
      ],
    ),
  );
}
