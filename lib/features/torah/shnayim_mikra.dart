import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/focus_mode.dart';
import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../home/today.dart';
import 'torah_settings.dart';
import 'verse_snap.dart';

/// This week's Shnayim Mikra: the parsha of the coming Shabbat (or of the
/// next Shabbat without a holiday reading) and today's aliyah, one a day
/// from the first on Sunday to the seventh on Shabbat.
({ParshaReading reading, HDate shabbat, int aliyah})? shnayimMikraWeek(HDate hd, bool il) {
  var shabbat = hd.onOrAfter(6);
  for (var i = 0; i < 8; i++) {
    final p = getSedra(shabbat.getFullYear(), il).lookup(shabbat);
    if (!p.chag && p.parsha.isNotEmpty) {
      final r = ParshaReading.of(p.parsha);
      return r == null ? null : (reading: r, shabbat: shabbat, aliyah: hd.getDay() + 1);
    }
    shabbat = shabbat.addDays(7);
  }
  return null;
}

/// A verse with its Targum Onkelos.
typedef MikraVerse = ({Verse at, String he, String targum});

const _books = ['Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy'];

/// Sefaria's ref for [r]'s verses, in the Torah or in Targum Onkelos.
String sefariaRange(ParshaReading r, {bool onkelos = false}) =>
    '${onkelos ? 'Onkelos_' : ''}${_books[r.book - 1]}.${r.begin.chapter}.${r.begin.verse}-${r.end.chapter}.${r.end.verse}';

/// The verses of a Sefaria text response for a range starting at [begin]:
/// a list of verses within one chapter, or a list of chapters across
/// several.
@visibleForTesting
List<(Verse, String)> sefariaVerses(List<int> body, Verse begin) {
  final j = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
  final text = (j['versions'] as List).cast<Map<String, Object?>>().where((v) => v['language'] == 'he').firstOrNull?['text'];
  final chapters = text is List && text.isNotEmpty && text.first is List ? text : [text is List ? text : const []];
  return [
    for (var c = 0; c < chapters.length; c++)
      for (final (v, t) in (chapters[c] as List).indexed)
        // Paragraph marks ({פ}, {ס}) are left out; the verses are shown apart.
        ((chapter: begin.chapter + c, verse: (c == 0 ? begin.verse : 1) + v), '$t'.replaceAll(RegExp(r'\s*\{[פס]\}\s*'), ' ').trim()),
  ];
}

/// The text of [r] with Onkelos, from Sefaria responses, gzipped for storage.
@visibleForTesting
List<int> packShnayimMikra(({String parsha, Verse begin, List<int> mikra, List<int> targum}) input) {
  final targum = {for (final (v, t) in sefariaVerses(input.targum, input.begin)) v: t};
  return GZipEncoder().encodeBytes(utf8.encode(jsonEncode({
    'parsha': input.parsha,
    'verses': [
      for (final (v, t) in sefariaVerses(input.mikra, input.begin)) [v.chapter, v.verse, t, targum[v] ?? ''],
    ],
  })));
}

@visibleForTesting
({String parsha, List<MikraVerse> verses}) unpackShnayimMikra(List<int> bytes) {
  final j = jsonDecode(utf8.decode(GZipDecoder().decodeBytes(bytes))) as Map<String, Object?>;
  return (
    parsha: j['parsha'] as String,
    verses: [
      for (final v in (j['verses'] as List).cast<List>())
        (at: (chapter: v[0] as int, verse: v[1] as int), he: v[2] as String, targum: v[3] as String),
    ],
  );
}

/// Only the latest parsha is kept: one download covers the week.
const _blobKey = 'shnayim-mikra';

/// The verses of a parsha (named as in [ParshaReading.parsha], joined with
/// "-"), downloaded from Sefaria the first time.
final shnayimMikraProvider = FutureProvider.family<List<MikraVerse>, String>((ref, parsha) async {
  final storage = ref.read(storageProvider);
  final stored = storage.readBlob(_blobKey);
  if (stored != null) {
    final s = await compute(unpackShnayimMikra, stored);
    if (s.parsha == parsha) return s.verses;
  }
  final r = ParshaReading.of(parsha.split('-'))!;
  final client = http.Client();
  try {
    Future<List<int>> get(String ref) async {
      final res = await client.get(Uri.parse('https://www.sefaria.org/api/v3/texts/$ref?version=hebrew&return_format=text_only'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return res.bodyBytes;
    }

    final (mikra, targum) = await (get(sefariaRange(r)), get(sefariaRange(r, onkelos: true))).wait;
    final packed = await compute(packShnayimMikra, (parsha: parsha, begin: r.begin, mikra: mikra, targum: targum));
    await storage.writeBlob(_blobKey, packed);
    analytics.event('shnayim_mikra_download', {'parsha': parsha});
    return (await compute(unpackShnayimMikra, packed)).verses;
  } finally {
    client.close();
  }
});

String _day(BuildContext context, int aliyah) =>
    context.tr(const ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Shabbat'][aliyah - 1]);

/// Today's Shnayim Mikra, for the Torah tab.
class ShnayimMikraTile extends ConsumerWidget {
  const ShnayimMikraTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final week = shnayimMikraWeek(t.hdate, il);
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimaryContainer;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.auto_stories, color: on),
        title: Text(context.tr('Shnayim Mikra'), style: theme.textTheme.titleMedium?.copyWith(color: on, fontWeight: FontWeight.w600)),
        subtitle: Text(
            week == null
                ? context.tr('No reading today')
                : '${renderParshaName(week.reading.parsha, context.hebcalLocale)} · '
                    '${context.tr('Aliyah {n}', {'n': week.aliyah})} · ${_day(context, week.aliyah)}',
            style: TextStyle(color: on)),
        trailing: week == null ? null : Icon(Icons.chevron_right, color: on),
        onTap: week == null ? null : () => context.push('/torah/shnayim-mikra'),
      ),
    );
  }
}

/// The week's parsha, an aliyah at a time: each verse twice, then its
/// Targum Onkelos. Opens on today's aliyah.
class ShnayimMikraScreen extends ConsumerStatefulWidget {
  const ShnayimMikraScreen({super.key});

  @override
  ConsumerState<ShnayimMikraScreen> createState() => _ShnayimMikraScreenState();
}

class _ShnayimMikraScreenState extends ConsumerState<ShnayimMikraScreen> with FocusModeReader {
  int? _aliyah;
  final _verseKeys = <GlobalKey>[];

  List<GlobalKey> _keys(int n) {
    while (_verseKeys.length < n) {
      _verseKeys.add(GlobalKey());
    }
    return _verseKeys.sublist(0, n);
  }

  /// The aliyah's verses, each built by [verse] with its snap key, and the
  /// credit below them.
  Widget _verses(List<MikraVerse> verses, bool snap, Widget Function(MikraVerse, GlobalKey) verse) {
    final keys = _keys(verses.length);
    final theme = Theme.of(context);
    return VerseSnap(
      verses: keys,
      enabled: snap,
      child: ListView.builder(
        // A fresh list for each aliyah, from its top.
        key: ValueKey(_aliyah),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: verses.length + 1,
        itemBuilder: (context, i) => i < verses.length
            ? verse(verses[i], keys[i])
            : Text(context.tr('Text and Targum Onkelos from Sefaria.'),
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(todaySnapshotProvider);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final week = shnayimMikraWeek(t.hdate, il);
    final theme = Theme.of(context);
    if (week == null) {
      return Scaffold(appBar: AppBar(title: Text(context.tr('Shnayim Mikra'))), body: Center(child: Text(context.tr('No reading today'))));
    }
    final r = week.reading;
    final aliyah = _aliyah ?? week.aliyah;
    final name = r.parsha.join('-');
    final text = ref.watch(shnayimMikraProvider(name));
    final s = ref.watch(torahSettingsProvider);
    final colors = SiddurColors.of(context);
    final heStyle = TextStyle(fontFamily: s.hebrewFont, fontSize: 21 * s.textScale, height: 1.6, color: theme.colorScheme.onSurface);
    final targumStyle = heStyle.copyWith(fontSize: 18 * s.textScale, color: theme.colorScheme.onSurfaceVariant);
    String nikud(String he) => s.showNikud ? he : stripNikud(he);

    final (from, to) = r.aliyot[aliyah - 1];
    int key(Verse v) => v.chapter * 1000 + v.verse;
    bool inAliyah(Verse v) => key(v) >= key(from) && key(v) <= key(to);

    final bar = AppBar(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('Shnayim Mikra')),
        Text(renderParshaName(r.parsha, context.hebcalLocale), style: theme.textTheme.bodySmall),
      ]),
      actions: [
        IconButton(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showTorahTextSettings(context)),
      ],
    );

    Widget body = switch (text) {
      AsyncData(:final value) => _verses(value.where((v) => inAliyah(v.at)).toList(), s.snapToVerse, (v, key) => Container(
              key: key,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              // The siddur's "said today" colors, for today's aliyah.
              decoration: aliyah == week.aliyah
                  ? BoxDecoration(
                      color: colors.todayFill,
                      borderRadius: BorderRadius.circular(10),
                      border: BorderDirectional(start: BorderSide(color: colors.todayBar, width: 3)),
                    )
                  : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < 2; i++)
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${gematriya(v.at.chapter)}:${gematriya(v.at.verse)} ',
                          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 14 * s.textScale)),
                      TextSpan(text: nikud(v.he)),
                    ]),
                    textDirection: TextDirection.rtl,
                    style: heStyle,
                  ),
                if (v.targum.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'ת״א ', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 14 * s.textScale)),
                      TextSpan(text: nikud(v.targum)),
                    ]),
                    textDirection: TextDirection.rtl,
                    style: targumStyle,
                  ),
                ],
              ]),
            )),
      AsyncError() => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(context.tr('Download failed. Check your connection and try again.'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(shnayimMikraProvider(name)), child: Text(context.tr('Retry'))),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(context.tr('Open on Sefaria')),
                onPressed: () => launchUrl(Uri.parse('https://www.sefaria.org/${sefariaRange(r)}')),
              ),
            ]),
          ),
        ),
      _ => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(context.tr('Downloading from Sefaria…')),
          ]),
        ),
    };

    return Scaffold(
      body: Column(children: [
        FocusModeBars(child: bar),
        // The week's seven aliyot by day; today's is marked.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            for (var n = 1; n <= 7; n++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  avatar: n == week.aliyah ? const Icon(Icons.today, size: 16) : null,
                  label: Text('$n · ${_day(context, n)}'),
                  selected: n == aliyah,
                  onSelected: (_) => setState(() => _aliyah = n),
                ),
              ),
          ]),
        ),
        Expanded(child: FocusModeBody(child: DoubleTapListener(onDoubleTap: toggleFocusMode, child: body))),
      ]),
    );
  }
}
