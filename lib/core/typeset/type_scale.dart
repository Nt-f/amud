import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import '../settings.dart';

/// What a paragraph is, as far as setting it goes. A printed siddur sets
/// the Shema larger than the blessings around it, a whispered line
/// smaller, the rubrics in small type that hugs the words they introduce;
/// the role carries that intent from the text to the page.
enum ParagraphRole {
  /// The first line said in a section: opens with an enlarged word.
  opening,

  /// Ordinary liturgy.
  body,

  /// The Shema's first verse: the largest line on the page, centered,
  /// as printed siddurim set it.
  proclamation,

  /// A line the whole service turns on (Barchu, Kedushah's verses): set
  /// larger, centered, with air around it.
  keystone,

  /// A blessing's closing ("Baruch atah… ") on its own: a touch larger,
  /// with a little more space after, as it ends a thought.
  blessing,

  /// The congregation's response.
  response,

  /// Said in an undertone ("Baruch shem kevod…"): smaller, centered
  /// under the verse it answers.
  undertone,

  /// Said only in the chazzan's repetition.
  chazarah,

  /// One of several alternatives ("On Rosh Chodesh: …").
  option,

  /// A rubric: "On Rosh Chodesh say:", "Bow here".
  instruction,

  /// A halachic note.
  note,

  /// A role label: "Chazzan:".
  speaker;

  /// Words that are said, as opposed to words about them.
  bool get said => switch (this) { instruction || note || speaker => false, _ => true };
}

/// How a paragraph sits in its column.
enum ParagraphAlign { justify, start, end, center }

/// An alignment the text itself asks for (the corpus's `align`), or null.
ParagraphAlign? explicitAlign(String? name) => switch (name) {
      'start' => ParagraphAlign.start,
      'end' => ParagraphAlign.end,
      'center' => ParagraphAlign.center,
      'justify' => ParagraphAlign.justify,
      _ => null,
    };

/// The reader's type: a size, leading, space and alignment for each
/// [ParagraphRole], derived from one body size so the page keeps a single
/// rhythm at any text scale.
///
/// With [print] off it reproduces the reader's plain setting (one size,
/// fixed gaps, ragged lines), so the same code serves both.
@immutable
class TypeScale {
  /// Body sizes, already multiplied by the reader's text scale.
  final double hebrewSize;
  final double latinSize;

  /// Print-style setting on.
  final bool print;

  /// Justify said text and notes.
  final bool justify;

  /// 0 (every paragraph the body size) to 1 (pronounced differences).
  final double contrast;

  const TypeScale({
    required this.hebrewSize,
    required this.latinSize,
    this.print = true,
    this.justify = true,
    this.contrast = 0.5,
  });

  /// The app's typesetting preferences; a reader with its own sizes (the
  /// Torah library) passes them in.
  factory TypeScale.of(AppSettings s, {double? hebrewSize, double? latinSize}) => TypeScale(
        hebrewSize: hebrewSize ?? 22 * s.textScale,
        latinSize: latinSize ?? 16 * s.textScale,
        print: s.typesetting,
        justify: s.typesetting && s.justifyText,
        contrast: s.typesetting ? s.typeContrast.clamp(0.0, 1.0) : 0,
      );

  /// Each role's departure from the body size at full contrast. At the
  /// default contrast (0.5) these halve: an opening line 5% larger, the
  /// Shema 11%, an undertone 7% smaller — felt more than seen.
  static const _delta = {
    ParagraphRole.opening: 0.10,
    ParagraphRole.proclamation: 0.5,
    ParagraphRole.keystone: 0.22,
    ParagraphRole.blessing: 0.05,
    ParagraphRole.response: -0.04,
    ParagraphRole.undertone: -0.14,
    ParagraphRole.chazarah: -0.06,
    ParagraphRole.option: -0.05,
  };

  /// Size relative to the body. Rubrics and notes are small type whatever
  /// the contrast: they're read differently, not just less loudly.
  double scale(ParagraphRole role, {required bool hebrew}) {
    if (!role.said) return hebrew ? 0.7 : 0.85;
    return 1 + (_delta[role] ?? 0) * contrast;
  }

  double size(ParagraphRole role, {required bool hebrew}) => (hebrew ? hebrewSize : latinSize) * scale(role, hebrew: hebrew);

  /// Line height. Hebrew with te'amim stacks marks above and below the
  /// letters and needs more room; larger type needs proportionally less
  /// (the gap between lines is what the eye measures, not the ratio).
  double leading(ParagraphRole role, {required bool hebrew, bool marks = false}) {
    if (!print) return hebrew ? 1.65 : 1.5;
    if (!role.said) return hebrew ? 1.55 : 1.45;
    final k = scale(role, hebrew: hebrew);
    final base = hebrew ? (marks ? 1.8 : 1.68) : 1.52;
    return (base - (k - 1) * 0.9).clamp(1.35, 1.95);
  }

  /// One body line: the unit of the page's vertical rhythm.
  double get line => hebrewSize * 1.65;

  /// Space above and below a paragraph. Rubrics keep with what follows
  /// them; keystones stand apart; a blessing's close leaves a breath.
  EdgeInsets space(ParagraphRole role, {bool compact = false}) {
    if (!print) return EdgeInsets.symmetric(vertical: compact ? 3 : 5);
    final u = line * (compact ? 0.6 : 1);
    final (before, after) = switch (role) {
      ParagraphRole.opening => (0.42, 0.12),
      ParagraphRole.proclamation => (0.55, 0.3),
      ParagraphRole.keystone => (0.4, 0.4),
      ParagraphRole.blessing => (0.08, 0.3),
      ParagraphRole.response => (0.06, 0.12),
      ParagraphRole.undertone => (0.06, 0.16),
      ParagraphRole.instruction || ParagraphRole.speaker => (0.34, 0.03),
      ParagraphRole.note => (0.26, 0.26),
      _ => (0.08, 0.12),
    };
    return EdgeInsets.only(top: u * before, bottom: u * after);
  }

  ParagraphAlign align(ParagraphRole role) {
    if (!print) return ParagraphAlign.start;
    return switch (role) {
      ParagraphRole.proclamation || ParagraphRole.keystone || ParagraphRole.undertone => ParagraphAlign.center,
      ParagraphRole.instruction || ParagraphRole.speaker => ParagraphAlign.start,
      _ => justify ? ParagraphAlign.justify : ParagraphAlign.start,
    };
  }

  /// The opening word of a section, as a multiple of its line's size.
  double get openingWord => print ? 1.15 + 0.5 * contrast : 1;

  /// Clear space between the text and a control (a folded section, a
  /// note), so what's tapped never reads as part of what's said.
  double get controlGap => print ? line * 0.32 : 4;

  /// Space around a section break.
  double get sectionGap => print ? line * 0.9 : 20;

  /// The widest comfortable column: about 60 Hebrew characters, or two
  /// such columns side by side.
  double measure({required bool sideBySide}) => (sideBySide ? 1240.0 : 760.0) * (hebrewSize / 22).clamp(1.0, 1.6);

  /// Side margin for a page [width] wide: at least [min], and wider when
  /// that keeps the column to its [measure].
  double gutter(double width, {required double min, bool sideBySide = false}) {
    if (!print) return min;
    final m = measure(sideBySide: sideBySide);
    return width - 2 * min > m ? (width - m) / 2 : min;
  }

  @override
  bool operator ==(Object other) =>
      other is TypeScale &&
      other.hebrewSize == hebrewSize &&
      other.latinSize == latinSize &&
      other.print == print &&
      other.justify == justify &&
      other.contrast == contrast;

  @override
  int get hashCode => Object.hash(hebrewSize, latinSize, print, justify, contrast);
}
