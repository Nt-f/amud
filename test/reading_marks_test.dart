import 'dart:io';

import 'package:amud/core/settings.dart';
import 'package:amud/features/siddur/reading_marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every gesture the corpus allows is labelled in English and Hebrew, except the plain bow', () {
    final source = File('tool/corpus/source.py').readAsStringSync();
    final block = RegExp(r'GESTURES = \{([^}]*)\}').firstMatch(source)!.group(1)!;
    final ids = RegExp(r"'(\w+)'").allMatches(block).map((m) => m.group(1)!).toSet();
    const bilingual = AppSettings(notesLanguage: NotesLanguage.bilingual);
    const hebrew = AppSettings(notesLanguage: NotesLanguage.hebrew);
    for (final g in ids.where((g) => g != 'bow')) {
      final both = gestureLabel(bilingual, g);
      expect(both, isNotNull, reason: g);
      expect(both, contains(' · '), reason: g);
      expect(RegExp(r'[א-ת]').hasMatch(gestureLabel(hebrew, g)!), isTrue, reason: g);
      expect(RegExp(r'[A-Za-z]').hasMatch(gestureLabel(hebrew, g)!), isFalse, reason: g);
    }
    expect(gestureLabel(bilingual, 'bow'), isNull);
  });

  test('gesture labels follow the instruction language', () {
    expect(gestureLabel(const AppSettings(), 'three_steps_back'), 'Three steps back');
    expect(gestureLabel(const AppSettings(notesLanguage: NotesLanguage.hebrew), 'three_steps_back'), 'שלוש פסיעות לאחור');
  });
}
