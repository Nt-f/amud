// Port of @hebcal/hdate locale.ts + @hebcal/core locale.ts
// Dart port licensed under GPL-2.0-or-later.

import 'data/locale_data.g.dart';

/// Removes niqqud and cantillation marks from a Hebrew string.
String hebrewStripNikkud(String str) => str
    .replaceAll(RegExp('[֐-ֽ]'), '')
    .replaceAll(RegExp('[ֿ-ׇ]'), '');

const Map<String, String> _alias = {'h': 'he', 'a': 'ashkenazi', 's': 'en', '': 'en'};

/// A simple translation registry keyed by English msgid.
class Locale {
  Locale._();

  static final Map<String, Map<String, String>> _locales = _initLocales();

  static Map<String, Map<String, String>> _initLocales() {
    final noNikud = <String, String>{
      for (final e in poHe.entries) e.key: hebrewStripNikkud(e.value),
      ...poHeNoNikudOverride,
    };
    return {
      'en': <String, String>{},
      'ashkenazi': Map.of(poAshkenazi),
      'he': Map.of(poHe),
      'he-x-nonikud': noNikud,
    };
  }

  static String _check(String locale) =>
      (_alias[locale] ?? locale).toLowerCase();

  static String? lookupTranslation(String id, [String? locale]) {
    if (locale == null) return null;
    final loc = _locales[_check(locale)];
    final s = loc?[id];
    if (s != null && s.isNotEmpty) return s;
    return null;
  }

  static String gettext(String id, [String? locale]) =>
      lookupTranslation(id, locale) ?? id;

  static void addLocale(String locale, Map<String, String> data) {
    _locales[_check(locale)] = Map.of(data);
  }

  static void addTranslation(String locale, String id, String translation) {
    final loc = _locales[_check(locale)];
    if (loc == null) throw ArgumentError("Locale '$locale' not found");
    loc[id] = translation;
  }

  static void addTranslations(String locale, Map<String, String> data) {
    final loc = _locales[_check(locale)];
    if (loc == null) throw ArgumentError("Locale '$locale' not found");
    loc.addAll(data);
  }

  static List<String> getLocaleNames() => _locales.keys.toList()..sort();

  static bool hasLocale(String locale) => _locales.containsKey(_check(locale));

  static String ordinal(int n, [String? locale]) {
    final l = _check(locale ?? '');
    if (l == 'en' || l.startsWith('ashkenazi')) return _enOrdinal(n);
    if (isHebrewLocale(l)) return '$n';
    if (l == 'es') return '$nº';
    return '$n.';
  }

  static String _enOrdinal(int n) {
    const s = ['th', 'st', 'nd', 'rd'];
    final v = n % 100;
    // JS: s[(v - 20) % 10] || s[v] || s[0] where JS % keeps the sign.
    final a = (v - 20).remainder(10);
    if (a >= 0 && a < 4 && a != 0) return '$n${s[a]}';
    if (v < 4 && v != 0) return '$n${s[v]}';
    return '$n${s[0]}';
  }

  static bool isHebrewLocale([String? locale]) {
    if (locale == null) return false;
    return (_alias[locale] ?? locale).toLowerCase().startsWith('he');
  }

  static String stripNikkud(String str) => hebrewStripNikkud(str);
}
