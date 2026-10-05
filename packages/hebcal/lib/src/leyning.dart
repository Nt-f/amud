import 'data/aliyot.g.dart';

/// A verse of a book of the Torah.
typedef Verse = ({int chapter, int verse});

/// The Shabbat Torah reading of a parsha (or doubled parshiyot), in seven
/// aliyot, from Hebcal's leyning tables.
class ParshaReading {
  /// The parsha as named in [SedraResult.parsha]: `['Matot', 'Masei']`.
  final List<String> parsha;

  /// 1 = Bereshit … 5 = Devarim.
  final int book;

  /// The seven aliyot, first and last verse of each.
  final List<(Verse, Verse)> aliyot;

  const ParshaReading(this.parsha, this.book, this.aliyot);

  Verse get begin => aliyot.first.$1;
  Verse get end => aliyot.last.$2;

  /// The reading of [parsha], or null for a name Hebcal doesn't know.
  static ParshaReading? of(List<String> parsha) {
    final d = parshaAliyotData[parsha.join('-')];
    if (d == null) return null;
    Verse verse(String cv) {
      final [c, v] = cv.split(':');
      return (chapter: int.parse(c), verse: int.parse(v));
    }

    return ParshaReading(parsha, d.$1, [for (final (b, e) in d.$2) (verse(b), verse(e))]);
  }
}
