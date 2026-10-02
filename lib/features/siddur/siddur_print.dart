import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:siddur_engine/siddur_engine.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import 'siddur_providers.dart';
import 'today_plan.dart';
import 'prayer_insights.dart';

void openSiddurPrint(BuildContext context, HDate date) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SiddurPrintScreen(initialDate: date),
      ),
    );

class PrintSection {
  final String title;
  final List<RenderItem> items;
  const PrintSection(this.title, this.items);
}

/// PDF generation is independent of the print dialog, for offline export.
Future<Uint8List> createSiddurPdf({
  required HDate date,
  required String book,
  required List<PrintSection> sections,
  required List<VersionInfo> sources,
  required ByteData hebrewFont,
  required ByteData latinFont,
  PdfPageFormat format = PdfPageFormat.a4,
  bool showHebrew = true,
  bool showTranslation = false,
}) async {
  final he = pw.Font.ttf(hebrewFont);
  final en = pw.Font.ttf(latinFont);
  final document = pw.Document(
    title: 'Amud — ${date.render('en')}',
    author: 'Amud',
  );
  pw.Widget text(String value, {bool hebrew = false, double size = 12}) =>
      pw.Text(
        value,
        textDirection: hebrew ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        style: pw.TextStyle(
          font: hebrew ? he : en,
          fontFallback: [he],
          fontSize: size,
          lineSpacing: 3,
        ),
      );
  final widgets = <pw.Widget>[
    text('Amud · ${date.render('en')}', size: 20),
    text('${date.greg().toIso8601String().substring(0, 10)} · $book'),
    text('Evening services use the following Hebrew date.', size: 10),
    pw.SizedBox(height: 16),
    for (final section in sections) ...[
      text(section.title, size: 17),
      pw.SizedBox(height: 10),
      for (final item in section.items)
        ...switch (item) {
          HeadingItem h => [text(h.node.en, size: 14), pw.SizedBox(height: 6)],
          InsertedSectionItem i => [
            text(i.labelEn.isEmpty ? i.node.en : i.labelEn, size: 14),
          ],
          SegmentItem s when !s.excluded => [
            if (s.applicability == Applicability.unknown && s.labelEn != null)
              text('If: ${s.labelEn}', size: 10),
            for (final label in {
              for (final segment in [s.he, s.tr])
                if (segment != null)
                  for (final run in segment.runs)
                    if (run.applicability == Applicability.unknown &&
                        run.labelEn != null)
                      run.labelEn!,
            })
              text('If: $label', size: 10),
            if (resolvedText(s.he).isNotEmpty)
              text(
                resolvedText(s.he),
                hebrew: true,
                size: s.kind == SegmentKind.prayer ? 14 : 10,
              ),
            if (resolvedText(s.tr).isNotEmpty)
              text(
                resolvedText(s.tr),
                size: s.kind == SegmentKind.prayer ? 11 : 10,
              ),
            pw.SizedBox(height: 7),
          ],
          DynamicItem d when d.kind == 'omer' => [
            if (showHebrew && d.data['he'] != null)
              text('${d.data['he']}', hebrew: true),
            if (showTranslation && d.data['en'] != null)
              text('${d.data['en']}'),
          ],
          _ => <pw.Widget>[],
        },
      pw.SizedBox(height: 18),
    ],
    text('Text sources and licenses', size: 14),
    for (final source in sources)
      text(
        '${source.versionTitle} · ${source.license}${source.source == null ? '' : ' · ${source.source}'}',
        size: 9,
      ),
    text(
      'Texts supplied through Sefaria. Prepared with Amud · amud.page',
      size: 9,
    ),
  ];
  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(36),
      maxPages: 500,
      theme: pw.ThemeData.withFont(base: en, fontFallback: [he]),
      footer: (c) => text('${c.pageNumber} / ${c.pagesCount}', size: 9),
      build: (_) => widgets,
    ),
  );
  return document.save();
}

/// Resolves the selected services with the same date and customs as the reader.
Future<({List<PrintSection> sections, List<VersionInfo> sources})>
preparePrintSections({
  required TodayPlan plan,
  required HDate date,
  required AppSettings settings,
  required Set<String> selected,
  required bool hebrew,
  required bool translation,
  required Future<SiddurResolver> Function(String) resolverFor,
  required Future<VersionSelection> Function(String) versionsFor,
}) async {
  final sections = <PrintSection>[];
  final sources = <String, VersionInfo>{};
  for (final service in plan.services.where((s) => selected.contains(s.key))) {
    final items = <RenderItem>[];
    final seen = <String>{};
    for (final entry in service.entries) {
      final resolver = await resolverFor(entry.book);
      final versions = await versionsFor(entry.book);
      final resolved = resolver.resolve(
        entry.node,
        versions,
        (svc) => DayContext.forService(
          date,
          svc == Service.other
              ? (service.tonight ? Service.maariv : Service.shacharit)
              : svc,
          il: settings.location.il,
          minhagim: settings.minhagim,
        ),
        options: ResolveOptions(
          excluded: ExcludedDisplay.hide,
          showHebrew: hebrew,
          showTranslation: translation,
          showInstructions: true,
          showNotes: false,
          notesHebrew: hebrew,
          notesTranslation: translation,
        ),
      );
      items.addAll(resolved.where((item) => seen.add(item.key)));
      for (final node
          in resolved
              .whereType<SegmentItem>()
              .map((item) => item.node)
              .toSet()) {
        for (final list in [
          if (hebrew) versions.hebrew,
          if (translation) versions.translation,
        ]) {
          final (version, _) = versions.pick(list, node.path);
          if (version != null) sources[version.file] = version;
        }
      }
    }
    sections.add(
      PrintSection(
        '${service.en}${service.tonight ? ' · ${date.next().render('en')}' : ''}',
        items,
      ),
    );
  }
  return (sections: sections, sources: sources.values.toList());
}

class SiddurPrintScreen extends ConsumerStatefulWidget {
  final HDate initialDate;
  const SiddurPrintScreen({super.key, required this.initialDate});
  @override
  ConsumerState<SiddurPrintScreen> createState() => _SiddurPrintScreenState();
}

class _SiddurPrintScreenState extends ConsumerState<SiddurPrintScreen> {
  late HDate date = widget.initialDate;
  final selected = <String>{
    'shacharit',
    'musaf',
    'mincha',
    'shabbatEve',
    'maariv',
    'night',
  };
  bool hebrew = true;
  bool translation = false;
  bool busy = false;
  String? error;

  Future<void> _preview(TodayPlan plan) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final settings = ref.read(settingsProvider);
      final prepared = await preparePrintSections(
        plan: plan,
        date: date,
        settings: settings,
        selected: selected,
        hebrew: hebrew,
        translation: translation,
        resolverFor: (book) => ref.read(resolverProvider(book).future),
        versionsFor: (book) => ref.read(versionSelectionProvider(book).future),
      );
      final sections = prepared.sections;
      if (!sections.any(
        (s) => s.items.any(
          (i) =>
              i is SegmentItem &&
              (resolvedText(i.he).isNotEmpty || resolvedText(i.tr).isNotEmpty),
        ),
      )) {
        throw StateError('No text is available for these selections.');
      }
      final fonts = await Future.wait([
        rootBundle.load('assets/fonts/NotoSerifHebrew.ttf'),
        rootBundle.load('assets/fonts/FrankRuhlLibre.ttf'),
      ]);
      final printDate = date;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(context.tr('Print preview'))),
            body: PdfPreview(
              pdfFileName:
                  'amud-${printDate.greg().toIso8601String().substring(0, 10)}.pdf',
              canChangeOrientation: false,
              canDebug: false,
              build: (format) => createSiddurPdf(
                date: printDate,
                book: plan.book,
                sections: sections,
                sources: prepared.sources,
                hebrewFont: fonts[0],
                latinFont: fonts[1],
                format: format,
                showHebrew: hebrew,
                showTranslation: translation,
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = '${context.tr('Unable to prepare PDF')}: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(todayPlanProvider(date.abs()));
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Print siddur'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: Text(date.render('en')),
            subtitle: Text(date.greg().toIso8601String().substring(0, 10)),
            trailing: const Icon(Icons.event),
            onTap: busy
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date.greg(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2239),
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        date = HDate.fromDate(picked);
                        error = null;
                      });
                    }
                  },
          ),
          Text(
            context.tr(
              'Uses your selected siddur, text versions, location, and customs.',
            ),
          ),
          Text(context.tr('Evening prayers belong to the next Hebrew date.')),
          CheckboxListTile(
            title: Text(context.tr('Hebrew')),
            value: hebrew,
            onChanged: busy ? null : (v) => setState(() => hebrew = v!),
          ),
          CheckboxListTile(
            title: Text(context.tr('Translation')),
            value: translation,
            onChanged: busy ? null : (v) => setState(() => translation = v!),
          ),
          plan.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => TextButton(
              onPressed: () => ref.invalidate(todayPlanProvider(date.abs())),
              child: Text(context.tr('Unable to load prayers. Tap to retry.')),
            ),
            data: (p) => p == null
                ? Text(context.tr('No prayers available.'))
                : Column(
                    children: [
                      if (p.needsMachzor)
                        Text(
                          context.tr(
                            'This day requires a machzor; the bundled siddur does not contain the complete service.',
                          ),
                        ),
                      for (final service in p.services)
                        CheckboxListTile(
                          title: Text(context.term(service.en)),
                          value: selected.contains(service.key),
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                  if (v!) {
                                    selected.add(service.key);
                                  } else {
                                    selected.remove(service.key);
                                  }
                                }),
                        ),
                      FilledButton.icon(
                        onPressed:
                            busy ||
                                (!hebrew && !translation) ||
                                !p.services.any((s) => selected.contains(s.key))
                            ? null
                            : () => _preview(p),
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print),
                        label: Text(context.tr('Preview, print or save PDF')),
                      ),
                    ],
                  ),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
