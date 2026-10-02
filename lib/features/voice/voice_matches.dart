import '../../core/search.dart';
import '../search/search_sources.dart';

typedef VoicePrayerMatch = ({PrayerEntry entry, int score});

/// Match names and aliases together with parent service names in either script.
List<VoicePrayerMatch> voicePrayerMatches(
  String text,
  List<PrayerEntry> index,
  List<String> order,
) {
  final query = SearchQuery(
    text.replaceAll(RegExp(r'\b(?:in|from|of|the)\b'), ' '),
  );
  if (query.isEmpty) return [];
  final found = <VoicePrayerMatch>[];
  for (final entry in index) {
    final direct = query.scoreTarget(entry.target);
    final contextual = query.score([
      ...entry.target.folded,
      for (final parent in entry.path) ...[parent.en, parent.he],
    ]);
    final score = direct ?? contextual;
    if (score != null) {
      found.add((entry: entry, score: score * 10 + entry.path.length));
    }
  }
  int rank(String book) =>
      !order.contains(book) ? order.length : order.indexOf(book);
  found.sort((a, b) {
    final score = a.score.compareTo(b.score);
    return score != 0
        ? score
        : rank(a.entry.book).compareTo(rank(b.entry.book));
  });
  final seen = <String>{};
  return [
    for (final match in found)
      if (seen.add(
        '${match.entry.key}|${match.entry.path.map((p) => searchFold(p.en)).join('/')}',
      ))
        match,
  ];
}
