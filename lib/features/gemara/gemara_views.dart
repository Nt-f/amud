import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart' show gematriya;

import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import 'daf_page.dart';
import 'gemara_data.dart';
import 'gemara_settings.dart';
import 'gemara_text.dart';
import 'gemara_user.dart';
import 'interlinear.dart';

/// Text styles shared by every view of an amud.
class GemaraStyle {
  final TextStyle he;
  final TextStyle en;
  final TextStyle rashi;
  final TextStyle small;
  final Color accent;
  final Color muted;
  final bool nikud;
  final bool elucidation;
  const GemaraStyle({
    required this.he,
    required this.en,
    required this.rashi,
    required this.small,
    required this.accent,
    required this.muted,
    required this.nikud,
    required this.elucidation,
  });

  String hebrew(String s) => nikud ? s : stripNikud(s);

  TextStyle get heBold => he.copyWith(fontWeight: FontWeight.w700);
  TextStyle get literal => en.copyWith(fontWeight: FontWeight.w700);
  TextStyle get added => en.copyWith(fontWeight: FontWeight.w400);
}

/// "1" or "א" for a segment, by interface language.
String segmentLabel(BuildContext context, int i) => context.uiLanguage == UiLanguage.en ? '${i + 1}' : gematriya(i + 1);

/// English runs as spans: the literal translation bold, the rest plain;
/// without the elucidation only the literal translation and short filler.
List<InlineSpan> runSpans(List<Run> runs, GemaraStyle st) => [
      for (final r in runs)
        if (st.elucidation || r.kind != RunKind.explanation) ...[
          TextSpan(text: r.text, style: r.kind == RunKind.literal ? st.literal : st.added),
          const TextSpan(text: ' '),
        ],
    ];

/// Commentary marks after the words they quote: token index → (label,
/// color), from [commentAnchors].
typedef QuoteMarks = Map<int, List<(String, Color)>>;

/// A small "רש״י" after the words a comment quotes.
class _QuoteMark extends StatelessWidget {
  final String label;
  final Color color;
  final GemaraStyle style;
  const _QuoteMark(this.label, this.color, this.style);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            textDirection: TextDirection.rtl, style: style.rashi.copyWith(fontSize: (style.small.fontSize ?? 13) * 0.82, height: 1.25)),
      );
}

List<InlineSpan> _markSpans(QuoteMarks marks, int token, GemaraStyle st) => [
      for (final (label, color) in marks[token] ?? const <(String, Color)>[])
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: _QuoteMark(label, color, st)),
    ];

/// A segment's Hebrew. With the word-by-word layer, each word can be
/// tapped; [selectedWords] are shaded.
class HebrewWords extends StatefulWidget {
  final List<String> tokens;
  final GemaraStyle style;
  final void Function(int token)? onWord;
  final Set<int> selectedWords;
  final TextAlign align;
  final QuoteMarks quoteMarks;
  const HebrewWords({
    super.key,
    required this.tokens,
    required this.style,
    this.onWord,
    this.selectedWords = const {},
    this.align = TextAlign.start,
    this.quoteMarks = const {},
  });

  @override
  State<HebrewWords> createState() => _HebrewWordsState();
}

class _HebrewWordsState extends State<HebrewWords> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final st = widget.style;
    final shade = st.accent.withValues(alpha: 0.18);
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < widget.tokens.length; i++) ...[
          TextSpan(
            text: st.hebrew(widget.tokens[i]),
            style: widget.selectedWords.contains(i) ? TextStyle(backgroundColor: shade) : null,
            recognizer: widget.onWord == null ? null : (TapGestureRecognizer()..onTap = () => widget.onWord!(i)).also(_taps.add),
          ),
          ..._markSpans(widget.quoteMarks, i, st),
          const TextSpan(text: ' '),
        ],
      ]),
      style: st.he,
      textDirection: TextDirection.rtl,
      textAlign: widget.align,
    );
  }
}

extension _Also<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

/// One segment in a reading view.
class SegmentView extends ConsumerWidget {
  final DafText daf;
  final int index;
  final InterlinearSegment? words;
  final GemaraView view;
  final GemaraStyle style;
  final bool selected;

  /// In the day's portion (Mishnah Yomi, Kitzur Yomi).
  final bool today;
  final int? selectedWord;
  final void Function(int token) onWord;

  /// Tapping a passage opens or closes its details in place.
  final VoidCallback onSelect;

  /// Whether the details (highlight, note, Rashi, Tosafot) are open under it.
  final bool expanded;

  /// Press and hold: reader mode from this passage.
  final VoidCallback? onHold;
  const SegmentView({
    super.key,
    required this.daf,
    required this.index,
    required this.words,
    required this.view,
    required this.style,
    required this.selected,
    this.today = false,
    required this.selectedWord,
    required this.onWord,
    required this.onSelect,
    required this.expanded,
    this.onHold,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(gemaraSettingsProvider);
    final marks = ref.watch(gemaraMarksProvider);
    final place = DafPlace(daf.tractate, daf.amud, index);
    final highlight = marks.highlights[place.key];
    final note = marks.notes[place.key];
    final st = style;
    final ws = words != null && words!.hasWords ? words : null;
    final tokens = ws?.tokens ?? sourceTokens(daf.vocalizedAt(index));
    final runs = davidsonRuns(daf.englishAt(index));
    // Words sharing the tapped word's phrase are shaded with it.
    final phraseWords = <int>{
      if (selectedWord != null && ws != null)
        for (var i = 0; i < ws.tokens.length; i++)
          if (i == selectedWord || (ws.linkAt(selectedWord!) >= 0 && ws.linkAt(i) == ws.linkAt(selectedWord!))) i,
    };
    final markColors = dafMarkColors(theme);
    final quoteMarks = <int, List<(String, Color)>>{};
    for (final a in commentAnchors(daf, index, tokens)) {
      final info = commentaryInfo(a.id);
      (quoteMarks[a.to] ??= []).add((info.mark, info.inner ? markColors.inner : markColors.outer));
    }
    final hebrew = HebrewWords(tokens: tokens, style: st, onWord: ws == null ? null : onWord, selectedWords: phraseWords, quoteMarks: quoteMarks);
    final english = Text.rich(TextSpan(children: runSpans(runs, st)), style: st.en);

    final number = segmentLabel(context, index);
    final markers = _CommentMarkers(daf: daf, index: index, style: st, hasNote: note != null, expanded: expanded, onTap: onSelect);
    final details = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: expanded ? PassageDetails(daf: daf, index: index, style: st) : const SizedBox(width: double.infinity),
    );
    final inlineComments = [
      if (settings.inlineCommentary && !expanded) ...[
        for (final com in daf.commentaries)
          for (final c in com.at(index)) CommentView(comment: c, label: context.tr(com.info.en), style: st, compact: true),
      ],
    ];
    final noteText = note == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: st.small.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant)),
          );
    final fill = highlight != null
        ? highlightColors[highlight % highlightColors.length]
        : selected
            ? st.accent.withValues(alpha: 0.08)
            : today
                ? SiddurColors.of(context).todayFill
                : null;

    // Phrase by phrase and word by word read as one continuous text: no
    // boxes, the passage number in the flow, the marks at its end.
    if (ws != null && (view == GemaraView.phrase || view == GemaraView.interlinear)) {
      return InkWell(
        onTap: onSelect,
        onLongPress: onHold,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: EdgeInsets.only(bottom: view == GemaraView.interlinear ? 14 : 8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            view == GemaraView.phrase
                ? PhraseText(segment: ws, style: st, onWord: onWord, selected: phraseWords, number: number, quoteMarks: quoteMarks)
                : InterlinearWords(segment: ws, style: st, onWord: onWord, selected: phraseWords, number: number, quoteMarks: quoteMarks),
            Align(alignment: AlignmentDirectional.centerEnd, child: markers),
            ?noteText,
            ...inlineComments,
            details,
          ]),
        ),
      );
    }

    final body = switch (view) {
      // With the word layer, side by side goes phrase by phrase: each
      // Hebrew phrase opposite its English.
      GemaraView.sideBySide when ws != null => _SidePhrases(segment: ws, style: st, onWord: onWord, selected: phraseWords, quoteMarks: quoteMarks),
      GemaraView.sideBySide => Row(
          // English on the left and Hebrew on the right in any interface.
          textDirection: TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: english), const SizedBox(width: 14), Expanded(child: hebrew)],
        ),
      _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [hebrew, const SizedBox(height: 6), english]),
    };
    final needsWords = (view == GemaraView.phrase || view == GemaraView.interlinear) && tokens.isNotEmpty;

    return InkWell(
      onTap: onSelect,
      onLongPress: onHold,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: selected ? BorderDirectional(start: BorderSide(color: st.accent, width: 3)) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(number, style: st.small.copyWith(color: st.accent, fontWeight: FontWeight.w700)),
            const Spacer(),
            markers,
          ]),
          const SizedBox(height: 4),
          body,
          if (needsWords)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr('Word-by-word English isn\'t ready for this amud yet.'), style: st.small.copyWith(color: st.muted)),
            ),
          ?noteText,
          ...inlineComments,
          details,
        ]),
      ),
    );
  }
}

/// Side by side, phrase by phrase: a row per phrase, English on the left
/// and Hebrew on the right in any interface; added English runs in the
/// English column under its phrase.
class _SidePhrases extends StatelessWidget {
  final InterlinearSegment segment;
  final GemaraStyle style;
  final void Function(int token) onWord;
  final Set<int> selected;
  final QuoteMarks quoteMarks;
  const _SidePhrases({required this.segment, required this.style, required this.onWord, required this.selected, this.quoteMarks = const {}});

  @override
  Widget build(BuildContext context) {
    final st = style;
    final p = phrasesOf(segment);
    final lead = runSpans(p.lead, st);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (lead.isNotEmpty) Text.rich(TextSpan(children: lead), style: st.en),
      for (final ph in p.phrases)
        InkWell(
          onTap: () => onWord(ph.from),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: selected.contains(ph.from) ? st.accent.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      if (ph.english.isNotEmpty) TextSpan(text: '${ph.english} ', style: st.literal),
                      ...runSpans(ph.after, st),
                    ]),
                    style: st.en,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: st.hebrew(ph.hebrew)),
                      for (var t = ph.from; t < ph.to; t++) ..._markSpans(quoteMarks, t, st),
                    ]),
                    style: st.he,
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ],
            ),
          ),
        ),
    ]);
  }
}

/// Rashi and Tosafot on a passage as small marks in the page's colors
/// ("רש״י 2", "תוס׳ 1"); tapping one opens them under the passage.
class _CommentMarkers extends StatelessWidget {
  final DafText daf;
  final int index;
  final GemaraStyle style;
  final bool hasNote;
  final bool expanded;
  final VoidCallback onTap;
  const _CommentMarkers({
    required this.daf,
    required this.index,
    required this.style,
    required this.hasNote,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = dafMarkColors(Theme.of(context));
    final counts = [
      for (final c in daf.commentaries)
        if (c.at(index).isNotEmpty) (c.info.mark, c.at(index).length, c.info.inner ? colors.inner : colors.outer),
    ];
    Widget mark(String label, int n, Color color) => Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Text('$label $n',
                  textDirection: TextDirection.rtl, style: style.rashi.copyWith(fontSize: (style.small.fontSize ?? 13) * 1.05, height: 1.3)),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (hasNote) Icon(Icons.sticky_note_2_outlined, size: 15, color: style.accent),
      for (final (label, n, color) in counts) mark(label, n, color),
      if (counts.isNotEmpty || hasNote) Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: style.muted),
    ]);
  }
}

final _rli = String.fromCharCode(0x2067);
final _pdi = String.fromCharCode(0x2069);

/// ArtScroll-style elucidation: each Hebrew phrase in bold, then its
/// English, then what the translator adds.
class PhraseText extends StatefulWidget {
  final InterlinearSegment segment;
  final GemaraStyle style;
  final void Function(int token) onWord;
  final Set<int> selected;
  final String number;
  final QuoteMarks quoteMarks;
  const PhraseText({
    super.key,
    required this.segment,
    required this.style,
    required this.onWord,
    required this.selected,
    required this.number,
    this.quoteMarks = const {},
  });

  @override
  State<PhraseText> createState() => _PhraseTextState();
}

class _PhraseTextState extends State<PhraseText> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final st = widget.style;
    final p = phrasesOf(widget.segment);
    final shade = st.accent.withValues(alpha: 0.18);
    // Hebrew phrases are isolated (RIGHT-TO-LEFT ISOLATE … POP DIRECTIONAL
    // ISOLATE) so each reads right to left inside the English paragraph.
    return Text.rich(
      TextSpan(children: [
        if (widget.number.isNotEmpty)
          TextSpan(text: '${widget.number}  ', style: st.small.copyWith(color: st.accent, fontWeight: FontWeight.w700)),
        ...runSpans(p.lead, st),
        for (final ph in p.phrases) ...[
          TextSpan(
            text: '$_rli${st.hebrew(ph.hebrew)}$_pdi',
            style: st.heBold.copyWith(fontSize: st.en.fontSize! * 1.18, backgroundColor: widget.selected.contains(ph.from) ? shade : null),
            recognizer: (TapGestureRecognizer()..onTap = () => widget.onWord(ph.from)).also(_taps.add),
          ),
          for (var t = ph.from; t < ph.to; t++) ..._markSpans(widget.quoteMarks, t, st),
          const TextSpan(text: ' '),
          if (ph.english.isNotEmpty) TextSpan(text: '${ph.english} ', style: st.literal),
          ...runSpans(ph.after, st),
        ],
      ]),
      style: st.en,
    );
  }
}

/// Word by word: every word with its English under it.
class InterlinearWords extends StatelessWidget {
  final InterlinearSegment segment;
  final GemaraStyle style;
  final void Function(int token) onWord;
  final Set<int> selected;
  final String number;
  final QuoteMarks quoteMarks;
  const InterlinearWords({
    super.key,
    required this.segment,
    required this.style,
    required this.onWord,
    required this.selected,
    required this.number,
    this.quoteMarks = const {},
  });

  @override
  Widget build(BuildContext context) {
    final st = style;
    final glossStyle = st.small.copyWith(color: st.muted, height: 1.15);
    final width = (st.en.fontSize ?? 16) * 7.5;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (number.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: st.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(number, style: st.small.copyWith(color: st.accent, fontWeight: FontWeight.w700)),
          ),
        for (var i = 0; i < segment.tokens.length; i++) ...[
          InkWell(
            onTap: () => onWord(i),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              constraints: BoxConstraints(maxWidth: width),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: selected.contains(i) ? st.accent.withValues(alpha: 0.16) : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(st.hebrew(segment.tokens[i]), style: st.he, textDirection: TextDirection.rtl),
                Text(segment.glossAt(i) ?? '', style: glossStyle, textAlign: TextAlign.center, textDirection: TextDirection.ltr),
              ]),
            ),
          ),
          // After the last word a comment quotes: its mark.
          for (final (label, color) in quoteMarks[i] ?? const <(String, Color)>[]) _QuoteMark(label, color, st),
        ],
      ]),
    );
  }
}

/// One comment of Rashi or Tosafot: the opening words bold, then the rest,
/// with the English under it when there is one.
class CommentView extends StatelessWidget {
  final Comment comment;
  final String label;
  final GemaraStyle style;
  final bool compact;
  const CommentView({super.key, required this.comment, required this.label, required this.style, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final st = style;
    final (head, rest) = comment.split;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 6 : 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(
          TextSpan(children: [
            if (compact) TextSpan(text: '$label: ', style: st.small.copyWith(color: st.accent, fontWeight: FontWeight.w700)),
            if (head.isNotEmpty) TextSpan(text: '${plainText(head)} ', style: st.rashi.copyWith(fontWeight: FontWeight.w700)),
            TextSpan(text: plainText(rest), style: st.rashi),
          ]),
          textDirection: TextDirection.rtl,
        ),
        if (comment.en.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(plainText(comment.en), style: st.small.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}

/// The card shown for a tapped word: the word, its English, and the phrase
/// of the translation it belongs to.
class WordCard extends StatelessWidget {
  final InterlinearSegment segment;
  final int token;
  final GemaraStyle style;
  final VoidCallback onClose;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  const WordCard({super.key, required this.segment, required this.token, required this.style, required this.onClose, this.onPrevious, this.onNext});

  @override
  Widget build(BuildContext context) {
    final st = style;
    final theme = Theme.of(context);
    final link = segment.linkAt(token);
    final phrase = link >= 0 && link < segment.runs.length ? segment.runs[link].$2 : null;
    return Material(
      elevation: 6,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(children: [
            IconButton(tooltip: context.tr('Previous word'), icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(st.hebrew(segment.tokens[token]), style: st.heBold.copyWith(fontSize: (st.he.fontSize ?? 21) * 1.15), textDirection: TextDirection.rtl),
                Text(segment.glossAt(token) ?? '', style: st.literal, textAlign: TextAlign.center),
                if (phrase != null)
                  Text(context.tr('In the phrase: {phrase}', {'phrase': phrase}),
                      style: st.small.copyWith(color: st.muted), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            IconButton(tooltip: context.tr('Next word'), icon: const Icon(Icons.chevron_right), onPressed: onNext),
            IconButton(tooltip: context.tr('Close'), icon: const Icon(Icons.close), onPressed: onClose),
          ]),
        ),
      ),
    );
  }
}

/// A passage's details, opened in place under it: highlight, copy, the
/// reader's note, and its Rashi and Tosafot.
class PassageDetails extends ConsumerStatefulWidget {
  final DafText daf;
  final int index;
  final GemaraStyle style;
  const PassageDetails({super.key, required this.daf, required this.index, required this.style});

  @override
  ConsumerState<PassageDetails> createState() => _PassageDetailsState();
}

class _PassageDetailsState extends ConsumerState<PassageDetails> {
  late final TextEditingController _note;
  late bool _writing;

  DafPlace get _place => DafPlace(widget.daf.tractate, widget.daf.amud, widget.index);

  @override
  void initState() {
    super.initState();
    final note = ref.read(gemaraMarksProvider).notes[_place.key] ?? '';
    _note = TextEditingController(text: note);
    _writing = note.isNotEmpty;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.style;
    final theme = Theme.of(context);
    final d = widget.daf;
    final i = widget.index;
    final highlight = ref.watch(gemaraMarksProvider).highlights[_place.key];
    Widget heading(String s) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Text(s, style: st.small.copyWith(color: st.accent, fontWeight: FontWeight.w700)),
        );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: st.muted.withValues(alpha: 0.3)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var c = 0; c < highlightColors.length; c++)
            InkResponse(
              onTap: () => ref.read(gemaraMarksProvider.notifier).setHighlight(_place, highlight == c ? null : c),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: highlightColors[c].withValues(alpha: 0.9),
                child: highlight == c ? Icon(Icons.check, size: 15, color: theme.colorScheme.onSurface) : null,
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('My note'),
            icon: Icon(_writing ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined, size: 20),
            onPressed: () => setState(() => _writing = !_writing),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('Copy'),
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${plainText(d.vocalizedAt(i))}\n\n${plainText(d.englishAt(i))}'));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Copied'))));
            },
          ),
        ]),
        if (_writing)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextField(
              controller: _note,
              minLines: 1,
              maxLines: 5,
              style: st.small,
              decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: context.tr('Write a note on this passage')),
              onChanged: (v) => ref.read(gemaraMarksProvider.notifier).setNote(_place, v),
            ),
          ),
        for (final com in d.commentaries)
          if (com.at(i).isNotEmpty) ...[
            heading(context.tr(com.info.en)),
            for (final c in com.at(i)) CommentView(comment: c, label: context.tr(com.info.en), style: st),
          ],
      ]),
    );
  }
}
