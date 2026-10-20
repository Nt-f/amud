import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';

/// What a manifest book is for, which decides where the Siddur tab lists it
/// and how much it counts when a prayer is looked up.
enum BookKind {
  /// A nusach to pray from.
  nusach,

  /// A Shabbat-only siddur: found after every other siddur.
  shabbat,

  /// English commentary (Rabbi Sacks on Siddur), not a siddur to pray from.
  commentary,
}

BookKind bookKind(String title) {
  final t = title.toLowerCase();
  if (t.contains(' on ')) return BookKind.commentary;
  if (t.contains('shabbat')) return BookKind.shabbat;
  return BookKind.nusach;
}

/// Commentary is English only: it opens in English text mode whatever the
/// reader's layout setting, which stays for the siddurim.
bool forcesEnglish(String book) => bookKind(book) == BookKind.commentary;

/// The Sefardi siddur (Edot HaMizrach; Nusach Sefard is Chassidic and
/// isn't), set in its own font (see [AppSettings.sefardiFont]).
bool isSefardiBook(String book) => book.contains('Edot HaMizrach');

/// The settings the reader of [book] uses.
AppSettings readerSettings(AppSettings s, String book) {
  if (forcesEnglish(book) && s.layout != TextLayout.translationOnly) return s.copyWith(layout: TextLayout.translationOnly);
  if (isSefardiBook(book) && s.sefardiFont.isNotEmpty && s.sefardiFont != s.hebrewFont) return s.copyWith(hebrewFont: s.sefardiFont);
  return s;
}

/// The book being read, for the widgets of its reader (overridden there);
/// null elsewhere.
final readerBookProvider = Provider<String?>((ref) => null);

/// The settings as the current reader uses them ([readerSettings] of
/// [readerBookProvider]): the app's settings outside a reader.
final readerSettingsProvider = Provider<AppSettings>((ref) {
  final s = ref.watch(settingsProvider);
  final book = ref.watch(readerBookProvider);
  return book == null ? s : readerSettings(s, book);
}, dependencies: [readerBookProvider]);
