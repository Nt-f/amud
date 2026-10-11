import 'dart:io';

import 'package:amud/features/gemara/daf_layout.dart';
import 'package:amud/features/gemara/gemara_data.dart';
import 'package:amud/features/gemara/gemara_perakim.dart';
import 'package:amud/features/gemara/gemara_text.dart';
import 'package:amud/features/gemara/gemara_settings_sheet.dart';
import 'package:amud/features/gemara/gemara_user.dart';
import 'package:amud/features/gemara/interlinear.dart';
import 'package:amud/features/gemara/gemara_settings.dart';
import 'package:amud/features/gemara/study_book.dart';
import 'package:flutter_test/flutter_test.dart';

// Berakhot 2a, segment 1, as Sefaria serves it.
const he = 'וַחֲכָמִים אוֹמְרִים: עַד חֲצוֹת.';
const en =
    '<b>The Rabbis say:</b> The time for the recitation of the evening <i>Shema</i> is <b>until midnight.</b>';

void main() {
  group('amud numbering and tractates', () {
    test('amud names and numbers round-trip', () {
      expect(amudNumber('2a'), 3);
      expect(amudNumber('2b'), 4);
      expect(amudName(127), '64a');
      expect(amudNumber('x'), isNull);
    });

    test('tractate table', () {
      final b = tractateNamed('Berakhot')!;
      expect(b.amudim.first, '2a');
      expect(b.amudim.last, '64a');
      expect(b.amudCount, 125);
      expect(b.dafCount, 63);
      expect(tractateNamed('Tamid')!.dafCount, 9);
      expect(tractateNamed('Tamid')!.amudim.first, '25b');
      expect(tractateNamed('Bava Metzia')!.contains('119b'), isFalse);
      // Hebcal's Daf Yomi spellings.
      expect(tractateNamed('Berachot')!.sefaria, 'Berakhot');
      expect(tractateNamed('Baba Batra')!.sefaria, 'Bava Batra');
    });
  });

  group('English runs', () {
    test('bold is literal, short plain is filler, long plain is explanation', () {
      expect(davidsonRuns(en), const [
        Run(RunKind.literal, 'The Rabbis say:'),
        Run(RunKind.explanation, 'The time for the recitation of the evening Shema is'),
        Run(RunKind.literal, 'until midnight.'),
      ]);
      expect(davidsonRuns('Hillel <b>said to him</b>: <b>My son</b>'), const [
        Run(RunKind.filler, 'Hillel'),
        Run(RunKind.literal, 'said to him: My son'),
      ]);
    });

    test('source tokens split like the server', () {
      expect(sourceTokens('<big><strong>מֵאֵימָתַי</strong></big> קוֹרִין&nbsp;אֶת'), ['מֵאֵימָתַי', 'קוֹרִין', 'אֶת']);
      expect(sourceTokens(he), ['וַחֲכָמִים', 'אוֹמְרִים:', 'עַד', 'חֲצוֹת.']);
    });
  });

  group('phrase by phrase', () {
    final seg = InterlinearSegment(
      tokens: const ['וַחֲכָמִים', 'אוֹמְרִים:', 'עַד', 'חֲצוֹת.'],
      glosses: const ['and the Rabbis', 'say', 'until', 'midnight'],
      links: const [0, 0, 2, 2],
      runs: const [('lit', 'The Rabbis say:'), ('note', 'The time for the evening Shema is'), ('lit', 'until midnight.')],
      ok: true,
    );

    test('groups words by literal phrase and hangs added English after it', () {
      final p = phrasesOf(seg);
      expect(p.lead, isEmpty);
      expect([for (final x in p.phrases) (x.hebrew, x.english)], [
        ('וַחֲכָמִים אוֹמְרִים:', 'The Rabbis say:'),
        ('עַד חֲצוֹת.', 'until midnight.'),
      ]);
      expect(p.phrases.first.after, const [Run(RunKind.explanation, 'The time for the evening Shema is')]);
    });

    test('a word linked backwards to an earlier phrase shows its own gloss', () {
      // Four words; the third claims phrase 0 again after phrase 2.
      final s = InterlinearSegment(
        tokens: const ['א', 'ב', 'ג', '—'],
        glosses: const ['a', 'b', 'c', '-'],
        links: const [0, 2, 0, -1],
        runs: const [('lit', 'A'), ('fill', 'and'), ('lit', 'B')],
        ok: true,
      );
      expect([for (final x in phrasesOf(s).phrases) x.english], ['A', 'B', 'c']);
      expect(phrasesOf(s).phrases.last.hebrew, 'ג —');
    });

    test('words in no phrase show their own glosses; a failed segment has no phrases', () {
      final loose = InterlinearSegment(tokens: seg.tokens, glosses: seg.glosses, links: const [0, 0, -1, -1], runs: seg.runs, ok: true);
      expect(phrasesOf(loose).phrases.last.english, 'until midnight');
      final failed = InterlinearSegment(tokens: seg.tokens, glosses: const [], links: const [], runs: seg.runs, ok: false);
      expect(phrasesOf(failed).phrases, isEmpty);
    });

    test('reads a server response and a stored envelope alike', () {
      final body = {
        'unit': '2a',
        'segments': [seg.toJson()],
        'meta': {'model': 'gemma4'},
      };
      expect(InterlinearUnit.fromJson(body).at(0)!.glossAt(3), 'midnight');
      expect(InterlinearUnit.fromJson({'parsed': body, 'model': 'gemma4'}).model, 'gemma4');
    });
  });

  group('page layout', () {
    double measure(DafWord w, DafColumn c) => w.text.length * (c == DafColumn.main ? 8.0 : 5.0) * w.scale;
    List<DafWord> words(int n, {int segment = 0}) => [for (var i = 0; i < n; i++) DafWord('word$i', segment: segment)];
    const opts = DafGeometryOptions(mainLineHeight: 20, sideLineHeight: 14, mainSpace: 4, sideSpace: 3);
    DafLayout lay(int main, int inner, int outer, {bool innerOnRight = true}) => layoutDaf(
          main: words(main),
          inner: words(inner),
          outer: words(outer),
          width: 600,
          innerOnRight: innerOnRight,
          options: opts,
          measure: measure,
        );

    test('every word is placed, inside the page, and nothing overlaps', () {
      for (final (m, i, o) in [(300, 400, 400), (600, 200, 300), (100, 600, 500), (300, 0, 400), (300, 10, 500)]) {
        final l = lay(m, i, o);
        expect(l.words.length, m + i + o);
        for (final w in l.words) {
          expect(w.x, greaterThanOrEqualTo(-0.01));
          expect(w.x + w.width, lessThanOrEqualTo(600.01));
        }
        for (var a = 0; a < l.words.length; a++) {
          for (var b = a + 1; b < l.words.length; b++) {
            final p = l.words[a];
            final q = l.words[b];
            final overlap = p.x < q.x + q.width - 0.5 && q.x < p.x + p.width - 0.5 && p.y < q.y + q.height - 0.5 && q.y < p.y + p.height - 0.5;
            if (overlap) fail('overlap in ($m, $i, $o): ${p.word.text}/${p.column} and ${q.word.text}/${q.column}');
          }
        }
      }
    });

    test('Rashi sits on the inner margin: right on amud a, left on amud b', () {
      double innerX(bool right) => lay(300, 400, 400, innerOnRight: right).words.where((w) => w.column == DafColumn.inner).last.x;
      expect(innerX(true), greaterThan(300));
      expect(innerX(false), lessThan(300));
    });

    test('the Gemara starts below the top band and the cases are told apart', () {
      final l = lay(300, 400, 400);
      expect(l.words.where((w) => w.column == DafColumn.main).first.y, 4 * 14);
      expect(lay(100, 600, 500).layoutCase, DafLayoutCase.doubleWrap);
      expect(lay(900, 100, 100).layoutCase, DafLayoutCase.doubleExtend);
    });

    test('a word is found by tapping it', () {
      final l = lay(50, 50, 50);
      final w = l.words.first;
      expect(l.hit(w.x + 1, w.y + 1), w);
    });

    test('HTML words: bold, big, footnotes dropped', () {
      final ws = wordsOfHtml('מתני׳ <big><strong>מאימתי</strong></big> קורין<sup class="footnote-marker">1</sup><i class="footnote">x y</i>', segment: 2);
      expect([for (final w in ws) w.text], ['מתני׳', 'מאימתי', 'קורין']);
      expect(ws[1].bold && ws[1].scale > 1, isTrue);
      expect(ws.every((w) => w.segment == 2), isTrue);
    });
  });

  test('server address gets a scheme', () {
    expect(serverAddress(' localhost:8787 '), 'http://localhost:8787');
    expect(serverAddress('https://talmud.dev'), 'https://talmud.dev');
    expect(serverAddress(''), '');
  });

  group('perakim', () {
    test('ranges from Sefaria refs, segments 0-based', () {
      expect(parseWholeRef('Berakhot 2a:1-13a:15'), (startAmud: '2a', startSegment: 0, endAmud: '13a', endSegment: 14));
      expect(parseWholeRef('Tamid 33a:8-14'), (startAmud: '33a', startSegment: 7, endAmud: '33a', endSegment: 13));
      expect(parseWholeRef('Tamid 33b:1-12')!.endAmud, '33b');
    });

    test('from the index, with names, and which perek a passage is in', () {
      const index = '{"alt_structs":{"Chapters":{"nodes":['
          '{"wholeRef":"Berakhot 2a:1-13a:15","titles":[{"lang":"en","text":"Chapter 1; MeEimatai","primary":true},{"lang":"he","text":"מאימתי","primary":true}]},'
          '{"wholeRef":"Berakhot 13a:16-17b:11","titles":[{"lang":"en","text":"Chapter 2; HaKoreh","primary":true},{"lang":"he","text":"היה קורא","primary":true}]}]}}}';
      final p = parsePerakim(index);
      expect([for (final x in p) (x.number, x.en, x.he)], [(1, 'MeEimatai', 'מאימתי'), (2, 'HaKoreh', 'היה קורא')]);
      expect(perekAt(p, '13a', 14)!.number, 1);
      expect(perekAt(p, '13a', 15)!.number, 2);
      expect(perekEndingOn(p, '17b')!.number, 2);
      expect(perekEndingOn(p, '5a'), isNull);
      expect(Perek.fromJson(p.first.toJson())!.endSegment, 14);
    });
  });

  group('tapping a word on the page', () {
    test('finds the same word in the vowelled layer, by position then spelling', () {
      const tokens = ['וַחֲכָמִים', 'אוֹמְרִים:', 'עַד', 'חֲצוֹת.'];
      expect(matchWord(tapped: 'עד', position: 2, pageWords: 4, tokens: tokens), 2);
      // Full spelling on the page, short in the layer, and an off-by-one guess.
      expect(matchWord(tapped: 'וחכמים', position: 1, pageWords: 4, tokens: tokens), 0);
      expect(matchWord(tapped: 'שבת', position: 0, pageWords: 4, tokens: tokens), isNull);
      expect(spellingKey('מְקָרֵב'), spellingKey('מקרוב'));
    });
  });

  group('Rashi opening words', () {
    test('split on the dash, or the first period', () {
      expect(const Comment('מאימתי קורין – כהנים שנטמאו', '').split, ('מאימתי קורין', 'כהנים שנטמאו'));
      expect(const Comment('עד חצות. כדמפרש בגמרא', '').split, ('עד חצות.', 'כדמפרש בגמרא'));
    });
  });

  group('reader marks', () {
    test('round-trip through JSON', () {
      const p = DafPlace('Berakhot', '2a', 3);
      final m = GemaraMarks(bookmarks: const [p], notes: {p.key: 'note'}, highlights: {p.key: 1}, history: const [p]);
      final back = GemaraMarks.fromJson(m.copyWith(completed: {'Berakhot:2a', 'Berakhot:2b', 'Berakhot:3a'}).toJson());
      expect(back.isComplete('Berakhot', '2b'), isTrue);
      // Daf 2 has both amudim done; daf 3 only one.
      expect(back.completedDafim('Berakhot', ['2a', '2b', '3a', '3b']), 1);
      expect(back.isBookmarked(const DafPlace('Berakhot', '2a')), isTrue);
      expect(back.notes[p.key], 'note');
      expect(back.resume, p);
    });
  });

  test('parses a real Sefaria response', () {
    final dir = Directory('test/fixtures/gemara');
    if (!dir.existsSync()) return;
    final d = parseDaf((
      tractate: 'Berakhot',
      amud: '2a',
      main: File('${dir.path}/berakhot_2a.json').readAsStringSync(),
      rashi: File('${dir.path}/rashi_berakhot_2a.json').readAsStringSync(),
      tosafot: File('${dir.path}/tosafot_berakhot_2a.json').readAsStringSync(),
    ));
    expect(d.length, 14);
    expect(d.vilna.first, contains('מאימתי'));
    expect(d.english[1], contains('<b>The Rabbis say:</b>'));
    expect(d.rashiAt(0).length, 2);
    expect(d.tosafotAt(0).length, 1);
    expect(DafText.fromJson(d.toJson()).rashiAt(4).length, d.rashiAt(4).length);
    // Sefaria's crowd-sourced English is left out; Jan Buckler's Tosafot stays.
    expect(d.commentary('rashi')!.credit, isEmpty);
    expect(d.rashiAt(0).first.en, isEmpty);
    expect(d.commentary('tosafot')!.credit, contains('Jan Buckler'));
    expect(DafText.fromJson(d.toJson()).commentary('tosafot')!.credit, d.commentary('tosafot')!.credit);
    expect(d.enCredit, contains('William Davidson'));
  });

  group('study books', () {
    test('every kind has its books and units', () {
      expect(booksOf(StudyKind.bavli).length, tractates.length);
      expect(booksOf(StudyKind.mishnah).length, 63);
      expect(studyBook('Mishnah Berakhot')!.units, ['1', '2', '3', '4', '5', '6', '7', '8', '9']);
      expect(studyBook(kitzurId)!.units.last, '221');
      expect(studyBook('Berachot')!.id, 'Berakhot');
      expect(studyBook('Mishnah Berakhot')!.neighbor('9', 1), isNull);
      expect(studyBook('Berakhot')!.neighbor('2b', 1), '3a');
      expect(studyBook(kitzurId)!.views, [GemaraView.elucidated, GemaraView.sideBySide]);
    });

    test("hebcal's Mishnah names map to Sefaria titles", () {
      expect(mishnahTitle('Avot'), 'Pirkei Avot');
      expect(mishnahTitle('Taanit'), "Mishnah Ta'anit");
      expect(studyBook(mishnahTitle('Bava Kamma')), isNotNull);
      for (final m in mishnahMasechtos) {
        expect(studyBook(m.id)!.kind, StudyKind.mishnah);
      }
    });

    test('each kind keeps its own view, among the views it has', () {
      final s = const GemaraSettings().withView('mishnah', GemaraView.phrase);
      expect(s.viewFor('mishnah', studyBook('Mishnah Berakhot')!.views), GemaraView.phrase);
      expect(s.viewFor('bavli', GemaraView.values), GemaraView.elucidated);
      expect(s.withView('kitzur', GemaraView.daf).viewFor('kitzur', studyBook(kitzurId)!.views), GemaraView.elucidated);
    });

    test('English without bold is plain and never hidden', () {
      expect(davidsonRuns('Upon awakening one should say Modeh Ani.'), const [Run(RunKind.plain, 'Upon awakening one should say Modeh Ani.')]);
    });

    test('a whole-book download splits into units, with their commentary', () {
      const main = '{"versions":['
          '{"language":"he","versionTitle":"Torat Emet 357","license":"Public Domain","text":[["משנה א","משנה ב"],["משנה ג"]]},'
          '{"language":"en","versionTitle":"William Davidson Edition - English","license":"CC-BY-NC","text":[["<b>One</b>","<b>Two</b>"],["<b>Three</b>"]]}]}';
      const bartenura = '{"versions":['
          '{"language":"he","versionTitle":"Torat-Emet","text":[[["<b>משנה</b>. פירוש"]],[[]]]},'
          '{"language":"en","versionTitle":"Bartenura on Mishnah, trans. by Rabbi Robert Alpert, 2020","license":"CC-BY","text":[[["Explanation"]],[[]]]}]}';
      final units = splitBook((kind: StudyKind.mishnah, book: 'Mishnah Orlah', main: main, commentaries: {'bartenura': bartenura}));
      expect([for (final (u, _) in units) u], ['1', '2']);
      final first = unpackUnit(units.first.$2);
      expect(first.vocalized, ['משנה א', 'משנה ב']);
      expect(first.english.first, '<b>One</b>');
      final b = first.commentary('bartenura')!;
      expect(b.at(0).single.split, ('משנה', 'פירוש'));
      expect(b.at(0).single.en, 'Explanation');
      expect(b.credit, contains('Alpert'));
      expect(first.heCredit, 'Torat Emet 357 (Public Domain)');
    });
  });

  group('placing a comment on the words it quotes', () {
    final tokens = 'מתני׳ מאימתי קורין את שמע בערבין. משעה שהכהנים נכנסים'.split(' ');
    test('finds the quote, with or without a trailing "וכו׳"', () {
      expect(anchorQuote('מאימתי קורין את שמע בערבין', tokens), (1, 5));
      expect(anchorQuote("מאימתי קורין וכו'", tokens), (1, 2));
      expect(anchorQuote('<b>משעה שהכהנים</b>', tokens), (6, 7));
    });

    test('vowels and full or short spelling do not matter', () {
      expect(anchorQuote('מֵאֵימָתַי קוֹרִין', tokens), (1, 2));
      expect(anchorQuote('שהכוהנים נכנסין', tokens), (7, 8));
    });

    test('refuses what it cannot place for sure', () {
      expect(anchorQuote('אמר רבא', 'אמר רבא כך ואמר רבא'.split(' ')), isNull, reason: 'twice in the passage');
      expect(anchorQuote('שמע ישראל', tokens), isNull, reason: 'only one word matches');
      expect(anchorQuote('וכו׳', tokens), isNull);
      expect(anchorQuote('קורן', tokens), isNull, reason: 'a one-word quote must match exactly');
    });

    test('on a real amud, Rashi and Tosafot land on the Gemara words', () {
      final dir = Directory('test/fixtures/gemara');
      final d = parseDaf((
        tractate: 'Berakhot',
        amud: '2a',
        main: File('${dir.path}/berakhot_2a.json').readAsStringSync(),
        rashi: File('${dir.path}/rashi_berakhot_2a.json').readAsStringSync(),
        tosafot: File('${dir.path}/tosafot_berakhot_2a.json').readAsStringSync(),
      ));
      final page = [for (final w in wordsOfHtml(d.vilnaAt(0), segment: 0)) w.text];
      final anchors = commentAnchors(d, 0, page);
      final tosafot = anchors.firstWhere((a) => a.id == 'tosafot');
      expect(page.sublist(tosafot.from, tosafot.to + 1).join(' '), 'מאימתי קורין');
      expect(anchors.where((a) => a.id == 'rashi'), isNotEmpty);
    });
  });
}
