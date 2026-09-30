import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';

final bookProvider = FutureProvider.family<BookInfo, String>((ref, title) async {
  final m = await ref.watch(manifestProvider.future);
  final b = m.book(title);
  if (b == null) throw StateError('Unknown book $title');
  return b;
});

final bookIndexProvider = FutureProvider.family<SchemaNode, String>((ref, title) async {
  final book = await ref.watch(bookProvider(title).future);
  return ref.watch(libraryProvider).index(book);
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
  final user = (lang == 'he' ? s.hebrewVersions : s.translationVersions)[book.title];
  final avail = availableVersions(book, lang, s);
  final titles = avail.map((v) => v.versionTitle).toSet();
  if (user != null && user.isNotEmpty) return user.where(titles.contains).toList();
  final rules = await ref.watch(rulesProvider.future);
  final defaults = ((rules[book.title] as Map?)?['defaultVersions'] as Map?)?[lang] as List?;
  final order = <String>[
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
  VersionInfo byTitle(String lang, String t) => book.byLanguage(lang).firstWhere((v) => v.versionTitle == t);
  var he = await Future.wait([for (final t in heOrder) lib.version(byTitle('he', t))]);
  if (ref.watch(settingsProvider.select((s) => s.preferTrop))) {
    bool trop(TextVersion v) => v.info.versionTitle.toLowerCase().contains('cantillation');
    he = [...he.where(trop), ...he.where((v) => !trop(v))];
  }
  final en = await Future.wait([for (final t in enOrder) lib.version(byTitle('en', t))]);
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
    'birkat': [r'birkat ha.?mazon', r'birchas? ha.?mazon', r'post meal blessing', r'grace after meals'],
    'bedtime': [r"keri.at shema al hamita", r'bedtime shema', r'prayer before retiring', r'shema before sleep'],
    'derech': [r'tefillat ha.?derech', r"traveler.?s prayer"],
    'omer': [r'sefirat ha.?omer', r'counting (?:of )?the omer'],
    'hallel': [r'^hallel$', r'/hallel$'],
    'havdalah': [r'havdal'],
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
  final rule = resolver.sectionRuleFor(node);
  if (rule != null && rule.when != 'true') {
    final unknown = <String>{};
    final ok = rule.condition.eval(contexts(SiddurResolver.serviceFor(node, fallback)).env, unknown);
    if (unknown.isNotEmpty) return (ap: Applicability.unknown, labelEn: rule.labelEn, labelHe: rule.labelHe);
    return (ap: ok ? Applicability.today : Applicability.notToday, labelEn: rule.labelEn, labelHe: rule.labelHe);
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
