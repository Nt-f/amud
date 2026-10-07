import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';

/// A book from the manifest. For Amud's own siddurim (assets/corpus) its
/// text, in each language, comes first as the version "Amud", before the
/// Sefaria versions it can be swapped for.
final bookProvider = FutureProvider.family<BookInfo, String>((ref, title) async {
  final m = await ref.watch(manifestProvider.future);
  final b = m.book(title);
  if (b == null) throw StateError('Unknown book $title');
  final corpus = await ref.watch(corpusProvider(b.title).future);
  if (corpus == null) return b;
  return BookInfo(b.title, corpus.heTitle, b.slug, b.indexFile, [
    for (final lang in const ['he', 'en']) ?corpus.versionInfo(lang),
    ...b.versions,
  ]);
});

/// A book's table of contents: the corpus's for Amud's own siddurim,
/// otherwise Sefaria's.
final bookIndexProvider = FutureProvider.family<SchemaNode, String>((ref, title) async {
  final book = await ref.watch(bookProvider(title).future);
  final corpus = await ref.watch(corpusProvider(book.title).future);
  return corpus?.index ?? await ref.watch(libraryProvider).index(book);
});

/// Versions available to the user for a book/language, honoring the
/// open-license filter.
List<VersionInfo> availableVersions(BookInfo book, String lang, AppSettings s) => [
      for (final v in book.byLanguage(lang))
        if (!s.openLicensesOnly || v.openLicense) v,
    ];

/// The effective ordered version titles for a book/language: the user's
/// choice, else the per-book defaults from rules.json, else the manifest
/// order (primary first, then most complete). Translations default to
/// untagged English only.
Future<List<String>> _effectiveOrder(Ref ref, BookInfo book, String lang) async {
  final s = ref.watch(settingsProvider);
  var user = (lang == 'he' ? s.hebrewVersions : s.translationVersions)[book.title];
  final avail = availableVersions(book, lang, s);
  final titles = avail.map((v) => v.versionTitle).toSet();
  if (user != null && user.contains(preCorpusVersions)) {
    // Chosen before Amud's own text: it goes where the first version it
    // was made from is, so a different version chosen first stays first.
    user = [...user]..remove(preCorpusVersions);
    final corpus = await ref.watch(corpusProvider(book.title).future);
    final sources = {for (final x in corpus?.editions[lang]?.sources ?? const <CorpusSource>[]) x.version.trim()};
    final i = user.indexWhere((t) => sources.contains(t.trim()));
    if (i >= 0 && !user.contains(corpusVersionTitle)) user.insert(i, corpusVersionTitle);
  }
  final chosen = user?.where(titles.contains).toList() ?? const [];
  if (chosen.isNotEmpty) return chosen;
  final rules = await ref.watch(rulesProvider.future);
  final defaults = ((rules[book.title] as Map?)?['defaultVersions'] as Map?)?[lang] as List?;
  final order = <String>[
    if (titles.contains(corpusVersionTitle)) corpusVersionTitle,
    ...?defaults?.cast<String>().where(titles.contains),
    for (final v in avail)
      if (lang == 'he' || v.languageTag == null) v.versionTitle,
  ];
  return order.toSet().toList();
}

final versionOrderProvider = FutureProvider.family<List<String>, (String, String)>((ref, args) async {
  final (title, lang) = args;
  final book = await ref.watch(bookProvider(title).future);
  return _effectiveOrder(ref, book, lang);
});

final versionSelectionProvider = FutureProvider.family<VersionSelection, String>((ref, title) async {
  final book = await ref.watch(bookProvider(title).future);
  final lib = ref.watch(libraryProvider);
  final heOrder = await ref.watch(versionOrderProvider((title, 'he')).future);
  final enOrder = await ref.watch(versionOrderProvider((title, 'en')).future);
  final corpus = await ref.watch(corpusProvider(book.title).future);
  Future<TextVersion> load(String lang, String t) {
    final v = book.byLanguage(lang).firstWhere((v) => v.versionTitle == t);
    return v.isCorpus ? Future.value(CorpusTextVersion(corpus!, v)) : lib.version(v);
  }

  var he = await Future.wait([for (final t in heOrder) load('he', t)]);
  if (ref.watch(settingsProvider.select((s) => s.preferTrop))) {
    bool trop(TextVersion v) => v.info.versionTitle.toLowerCase().contains('cantillation');
    he = [...he.where(trop), ...he.where((v) => !trop(v))];
  }
  final en = await Future.wait([for (final t in enOrder) load('en', t)]);
  return VersionSelection(he, en);
});

/// The book the Siddur tab opens by default.
final defaultBookProvider = FutureProvider<String>((ref) async {
  final m = await ref.watch(manifestProvider.future);
  final chosen = ref.watch(settingsProvider.select((s) => s.defaultBook));
  if (chosen != null && m.book(chosen) != null) return chosen;
  return (m.book('Siddur Ashkenaz') ?? m.books.first).title;
});

/// Finds a well-known section (shortcut key) for the day [contextFor]
/// describes: Shabbat's services on Shabbat and Yom Tov, where Friday
/// night's Maariv is Shabbat's and Saturday night's isn't.
String? findSectionOn(SchemaNode root, String key, DayContext Function(Service) contextFor) {
  final c = contextFor(key == 'maariv' ? Service.maariv : Service.shacharit);
  return findSection(root, key, shabbat: c['shabbat'] || c['yomTov']);
}

/// Finds a well-known section (shortcut key) within a book.
String? findSection(SchemaNode root, String key, {required bool shabbat}) {
  final patterns = <String, List<String>>{
    'shacharit': shabbat
        ? [r'^shabbat/shacharit$', r'shaharit for shabbat', r'^shabbat (?:shacharit|morning services?)$', r'^the morning prayers$', r'^shabbat[^/]*/(?:shacharit|shaharit)$']
        : [r'^weekday/shacharit$', r'weekday shacharit', r'^shacharit$', r'the morning prayers', r'weekdays$'],
    'mincha': shabbat
        ? [r'^shabbat/minchah?$', r'shabbat mincha', r'mincha service for shabbos', r'minha for shabbat']
        : [r'^weekday/minchah?$', r'weekday mincha', r'^mincha$', r'minha for weekdays'],
    'maariv': shabbat
        ? [r'^shabbat/maariv$', r'shabbat (?:eve )?(?:maariv|arvit)', r'maariv service for shabbos', r"ma'ariv for shabbat"]
        : [r'^weekday/maariv$', r'weekday (?:maariv|arvit)', r'^maariv$', r"ma'ariv for weekdays"],
    'musaf': [r'^shabbat/musaf', r'musaf leshabbat', r'shabbat mussaf', r'musaf for shabbat', r'^musaf service$', r'^musaf$'],
    // Whole titles first, so "Birchas Hamazon for Sheva Berachos" isn't
    // taken for the everyday one.
    'birkat': [
      r'(?:^|/)bir(?:k|ch)(?:at|as|os) ha.?mazon(?:;[^/]*)?$',
      r'(?:^|/)post meal blessing$',
      r'(?:^|/)grace after meals$',
      r'bir(?:k|ch)(?:at|as|os) ha.?mazon',
      r'post meal blessing',
      r'grace after meals',
    ],
    'bedtime': [r"keri.at shema al hamita", r'bedtime shema', r'prayer before retiring', r'shema before sleep'],
    'derech': [r'tefillat ha.?derech', r"traveler.?s prayer"],
    'omer': [r'sefirat ha.?omer', r'counting (?:of )?the omer'],
    'hallel': [r'^hallel$', r'/hallel$'],
    'havdalah': [r'havdal'],
    'birkatHaChama': [r'birkat ha.?chama', r'birkas ha.?chama', r'blessing of the sun'],
    'kiddushLevana': [r'birkat ha.?levana', r'kiddush levan', r'blessing of the (?:new )?moon'],
  }[key];
  if (patterns == null) return null;
  final all = root.descendants.toList();
  for (final p in patterns) {
    final re = RegExp(p, caseSensitive: false);
    for (final n in all) {
      if (re.hasMatch(n.id) || re.hasMatch(n.en)) return n.id;
    }
  }
  return null;
}

/// Whether [node] is said on the day [contexts] describes: by its own
/// section rule, or, for a section without one, by its parts: a section
/// all of whose parts are for other days (Selichot on an ordinary day)
/// isn't said, and one whose parts are all conditional and some said today
/// (Hoshanot) is. The labels say why.
({Applicability ap, String? labelEn, String? labelHe}) sectionStatus(
    SiddurResolver resolver, SchemaNode node, DayContext Function(Service) contexts,
    [Service fallback = Service.shacharit]) {
  final rule = resolver.effectiveRuleFor(node);
  if (rule != null && rule.when != 'true') {
    final ap = resolver.ruleApplicability(rule, contexts(SiddurResolver.serviceFor(node, fallback)));
    if (ap != Applicability.always) return (ap: ap, labelEn: rule.labelEn, labelHe: rule.labelHe);
    return (ap: Applicability.always, labelEn: null, labelHe: null);
  }
  if (rule != null || node.isLeaf) return (ap: Applicability.always, labelEn: null, labelHe: null);
  final svc = SiddurResolver.serviceFor(node, fallback);
  final parts = [for (final c in node.children) sectionStatus(resolver, c, contexts, svc)];
  if (parts.every((p) => p.ap == Applicability.notToday)) return (ap: Applicability.notToday, labelEn: null, labelHe: null);
  if (parts.every((p) => p.ap != Applicability.always)) {
    for (final p in parts) {
      if (p.ap == Applicability.today) return p;
    }
  }
  return (ap: Applicability.always, labelEn: null, labelHe: null);
}
