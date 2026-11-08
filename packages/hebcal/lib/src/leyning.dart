import 'data/aliyot.g.dart';

/// A verse of a book of the Torah.
typedef Verse = ({int chapter, int verse});

/// The Shabbat Torah reading of a parsha (or doubled parshiyot), in seven
/// aliyot, and its weekday reading in three, from Hebcal's leyning tables.
class ParshaReading {
  /// The parsha as named in [SedraResult.parsha]: `['Matot', 'Masei']`.
  final List<String> parsha;

  /// 1 = Bereshit … 5 = Devarim.
  final int book;

  /// The seven aliyot, first and last verse of each.
  final List<(Verse, Verse)> aliyot;

  /// What is read on Monday, Thursday and Shabbat afternoon: Kohen, Levi
  /// and Yisrael. For doubled parshiyot, the first parsha's.
  final List<(Verse, Verse)> weekday;

  const ParshaReading(this.parsha, this.book, this.aliyot, this.weekday);

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

    List<(Verse, Verse)> ranges(List<(String, String)> r) => [for (final (b, e) in r) (verse(b), verse(e))];
    final weekday = parshaWeekdayData[parsha.first];
    return ParshaReading(parsha, d.$1, ranges(d.$2), weekday == null ? ranges(d.$2).take(1).toList() : ranges(weekday));
  }
}
