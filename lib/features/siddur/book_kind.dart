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

/// The settings the reader of [book] uses.
AppSettings readerSettings(AppSettings s, String book) =>
    forcesEnglish(book) && s.layout != TextLayout.translationOnly ? s.copyWith(layout: TextLayout.translationOnly) : s;
