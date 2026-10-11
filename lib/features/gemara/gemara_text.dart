import '../../core/html_text.dart';
import 'interlinear.dart';

/// Kinds of English in a segment, as the William Davidson (Steinsaltz)
/// translation marks them: bold is the literal translation of the words on
/// the page, plain text is added. Short additions are filler ("is", "the
/// time for"), longer ones are explanation. English without such marking is
/// [RunKind.plain].
enum RunKind { literal, filler, explanation, plain }

class Run {
  final RunKind kind;
  final String text;
  const Run(this.kind, this.text);

  @override
  bool operator ==(Object other) => other is Run && other.kind == kind && other.text == text;
  @override
  int get hashCode => Object.hash(kind, text);
  @override
  String toString() => '${kind.name}:$text';
}

/// Plain runs up to this many words are filler; longer ones explanation
/// (the same rule as the interlinear server).
const fillerMaxWords = 4;

final _footnote = RegExp(r'<sup[^>]*class="footnote-marker"[^>]*>[\s\S]*?</sup>|<i[^>]*class="footnote"[^>]*>[\s\S]*?</i>');
final _tags = RegExp(r'<[^>]+>');
final _space = RegExp(r'\s+');

/// Sefaria HTML as plain text: footnotes dropped, tags removed, entities
/// decoded, whitespace collapsed.
String plainText(String html) =>
    SefariaHtml.decodeEntities(html.replaceAll(_footnote, '').replaceAll(RegExp(r'<br\s*/?>'), ' ').replaceAll(_tags, ''))
        .replaceAll(_space, ' ')
        .trim();

/// The source words of a segment, split exactly as the interlinear server
/// splits them (whitespace only; punctuation stays on its word).
List<String> sourceTokens(String html) => plainText(html).split(' ').where((w) => w.isNotEmpty).toList();

/// Splits Davidson English into runs. Adjacent runs of one kind merge, and a
/// plain run of punctuation joins the run before it ("**said**:").
List<Run> davidsonRuns(String html) {
  // English with no bold at all (the Kitzur's, say) isn't marked literal:
  // all of it is the translation, shown as is.
  if (!RegExp(r'<(b|strong)[\s>]').hasMatch(html)) {
    final text = plainText(html);
    return text.isEmpty ? const [] : [Run(RunKind.plain, text)];
  }
  final marked = html
      .replaceAll(_footnote, '')
      .replaceAll(RegExp(r'<br\s*/?>'), ' ')
      .replaceAll(RegExp(r'</?(b|strong)(\s[^>]*)?>'), '\u0001')
      .replaceAll(_tags, '');
  final runs = <Run>[];
  final parts = SefariaHtml.decodeEntities(marked).split('\u0001');
  for (var n = 0; n < parts.length; n++) {
    final text = parts[n].replaceAll(_space, ' ').trim();
    if (text.isEmpty) continue;
    final bold = n.isOdd;
    if (!bold && !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) {
      if (runs.isNotEmpty) {
        runs[runs.length - 1] = Run(runs.last.kind, '${runs.last.text}$text');
      } else {
        runs.add(Run(RunKind.filler, text));
      }
      continue;
    }
    final kind = bold
        ? RunKind.literal
        : text.split(' ').length <= fillerMaxWords
            ? RunKind.filler
            : RunKind.explanation;
    if (runs.isNotEmpty && runs.last.kind == kind) {
      runs[runs.length - 1] = Run(kind, '${runs.last.text} $text');
    } else {
      runs.add(Run(kind, text));
    }
  }
  return runs;
}

/// The runs the server sent, in the same type.
List<Run> interlinearRuns(InterlinearSegment s) => [
      for (final (t, text) in s.runs)
        Run(
          switch (t) {
            'lit' => RunKind.literal,
            'fill' => RunKind.filler,
            _ => RunKind.explanation,
          },
          text,
        ),
    ];

/// One step of a phrase-by-phrase reading: Hebrew words, then the English
/// for them, then any added English that follows.
class Phrase {
  /// Token range [from, to) in the segment.
  final int from;
  final int to;
  final String hebrew;

  /// The literal translation of these words (a phrase of the translation,
  /// or the words' own glosses when they belong to none).
  final String english;

  /// Added English after the literal translation: filler, explanation, and
  /// any literal phrase no word was linked to.
  final List<Run> after;
  const Phrase(this.from, this.to, this.hebrew, this.english, this.after);
}

/// Builds the phrase-by-phrase reading of a segment from its word layer:
/// consecutive words in the same literal phrase form one step. Leading added
/// English (before the first literal phrase) comes back as [lead].
({List<Run> lead, List<Phrase> phrases}) phrasesOf(InterlinearSegment s) {
  final runs = interlinearRuns(s);
  if (!s.hasWords) return (lead: runs, phrases: const []);
  final linked = {for (final l in s.links) if (l >= 0 && l < runs.length && runs[l].kind == RunKind.literal) l};

  // Each run hangs after the nearest linked literal run before it (or leads
  // the segment when there is none).
  final trailing = <int, List<Run>>{};
  final lead = <Run>[];
  var anchor = -1;
  for (var r = 0; r < runs.length; r++) {
    if (linked.contains(r)) {
      anchor = r;
      trailing[r] = [];
      continue;
    }
    (anchor < 0 ? lead : trailing[anchor]!).add(runs[r]);
  }

  // Group consecutive words by phrase, then keep only links that follow the
  // English in order (a longest increasing run of phrase numbers). A word
  // linked backwards usually took the wrong copy of a repeated phrase ("said
  // to him"); it shows its own gloss instead.
  final groups = <(int, int, int)>[];
  for (var i = 0; i < s.tokens.length;) {
    final link = linked.contains(s.linkAt(i)) ? s.linkAt(i) : -1;
    var j = i + 1;
    while (j < s.tokens.length && (linked.contains(s.linkAt(j)) ? s.linkAt(j) : -1) == link) {
      j++;
    }
    groups.add((i, j, link));
    i = j;
  }
  final kept = _increasing([for (final g in groups) g.$3]);

  final phrases = <Phrase>[];
  final shown = <int>{};
  for (var n = 0; n < groups.length; n++) {
    final (i, j, link) = groups[n];
    final hebrew = s.tokens.sublist(i, j).join(' ');
    if (link >= 0 && kept.contains(n) && shown.add(link)) {
      phrases.add(Phrase(i, j, hebrew, runs[link].text, trailing[link] ?? const []));
    } else {
      // Words outside any phrase, or out of order: their own glosses. A
      // dash or other mark with no Hebrew letter has nothing to gloss.
      final glosses = [
        for (var k = i; k < j; k++)
          if (_hebrewLetter.hasMatch(s.tokens[k])) s.glossAt(k) ?? '',
      ];
      phrases.add(Phrase(i, j, hebrew, glosses.join(' '), const []));
    }
  }
  // A dash or other mark with no Hebrew letter joins the phrase before it.
  final merged = <Phrase>[];
  for (final ph in phrases) {
    if (merged.isNotEmpty && !_hebrewLetter.hasMatch(ph.hebrew) && ph.english.isEmpty) {
      final last = merged.removeLast();
      merged.add(Phrase(last.from, ph.to, '${last.hebrew} ${ph.hebrew}', last.english, last.after));
    } else {
      merged.add(ph);
    }
  }
  return (lead: lead, phrases: merged);
}

final _hebrewLetter = RegExp('[\u05D0-\u05EA]');

/// Indices of a longest strictly increasing subsequence of the non-negative
/// values (negative values are never kept).
Set<int> _increasing(List<int> values) {
  final idx = [for (var i = 0; i < values.length; i++) if (values[i] >= 0) i];
  if (idx.isEmpty) return {};
  // O(n²) is plenty: a segment has at most a few dozen groups.
  final best = List.filled(idx.length, 1);
  final prev = List.filled(idx.length, -1);
  for (var a = 0; a < idx.length; a++) {
    for (var b = 0; b < a; b++) {
      if (values[idx[b]] < values[idx[a]] && best[b] + 1 > best[a]) {
        best[a] = best[b] + 1;
        prev[a] = b;
      }
    }
  }
  var end = 0;
  for (var a = 1; a < idx.length; a++) {
    if (best[a] > best[end]) end = a;
  }
  final out = <int>{};
  for (var a = end; a >= 0; a = prev[a]) {
    out.add(idx[a]);
  }
  return out;
}

/// Hebrew letters only, with ו and י after the first letter dropped, so
/// full and short spellings of a word compare equal.
String spellingKey(String word) {
  final letters = word.replaceAll(RegExp('[^\u05D0-\u05EA]'), '');
  if (letters.isEmpty) return '';
  return letters[0] + letters.substring(1).replaceAll(RegExp('[וי]'), '');
}

/// The word of the word-by-word layer that a tapped word of the printed
/// page is, or null. The page (Vilna, no vowels) and the word layer (the
/// vowelled edition) split a passage nearly the same way, so the guess is
/// the same relative position, then the nearest word spelled the same.
int? matchWord({required String tapped, required int position, required int pageWords, required List<String> tokens}) {
  if (tokens.isEmpty || pageWords <= 0) return null;
  final key = spellingKey(tapped);
  final guess = (position * tokens.length / pageWords).round().clamp(0, tokens.length - 1);
  if (key.isEmpty) return null;
  for (var d = 0; d <= 8; d++) {
    for (final i in [guess - d, guess + d]) {
      if (i >= 0 && i < tokens.length && spellingKey(tokens[i]) == key) return i;
    }
  }
  return null;
}

// ------------------------------------------------------------- quotations

/// Words that end a quotation without being part of it: "וכו׳", "כו׳",
/// "וגו׳", "וגומר" (as their spelling keys).
const _etc = {'וכ', 'כ', 'וג', 'ג', 'וגמר', 'כול'};

int _distance(String a, String b, int cap) {
  if ((a.length - b.length).abs() > cap) return cap + 1;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    var rowMin = i;
    for (var j = 1; j <= b.length; j++) {
      final v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
      cur.add(v);
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > cap) return cap + 1;
    prev = cur;
  }
  return prev[b.length];
}

String _letters(String w) => w.replaceAll(RegExp('[^\u05D0-\u05EA]'), '');

bool _sameWord(String a, String b) => a == b || (a.length >= 3 && b.length >= 3 && _distance(a, b, 1) <= 1);

/// Where a commentary's opening words (its dibur hamatchil) are among a
/// passage's [tokens], as a token range, or null when it can't be said for
/// sure: no match, or more than one equally good place. Precision over
/// recall: an unanchored comment stays on the whole passage.
///
/// Words compare by letters (no vowels, full and short spelling alike, one
/// slip in a longer word). A quote that ends in "וכו׳" counts when all its
/// words before that match; one cut short otherwise needs three matching
/// words.
(int, int)? anchorQuote(String quoteHtml, List<String> tokens) {
  final quote = [for (final w in plainText(quoteHtml).split(' ')) spellingKey(w)]..removeWhere((k) => k.isEmpty);
  while (quote.isNotEmpty && _etc.contains(quote.last)) {
    quote.removeLast();
  }
  if (quote.isEmpty) return null;
  final keys = [for (final t in tokens) spellingKey(t)];
  var best = 0;
  final starts = <int>[];
  for (var s = 0; s < keys.length; s++) {
    var m = 0;
    while (m < quote.length && s + m < keys.length && (keys[s + m].isEmpty || _sameWord(keys[s + m], quote[m]))) {
      // A mark with no letters (a dash) in the passage is skipped over.
      m++;
    }
    if (m == 0) continue;
    if (m > best) {
      best = m;
      starts
        ..clear()
        ..add(s);
    } else if (m == best) {
      starts.add(s);
    }
  }
  final enough = best == quote.length || best >= 3;
  if (!enough || starts.length != 1) return null;
  // A one-word quote must match exactly, not within a slip.
  if (quote.length == 1 && _letters(tokens[starts.single]) != plainText(quoteHtml).split(' ').map(_letters).firstWhere((w) => w.isNotEmpty)) return null;
  return (starts.single, starts.single + best - 1);
}
