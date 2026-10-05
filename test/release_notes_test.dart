import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release notes are read by people, so they should sound like a person
/// wrote them (see release-notes/README.md). Notes up to [_checkedAfter]
/// were written before these checks and are left as they are.
const _checkedAfter = [0, 7, 0];

const _maxWords = 40;

/// Words that make notes read like an advertisement.
final _filler = RegExp(
    r'\b(seamless(ly)?|effortless(ly)?|robust|intuitive|elevates?|streamlined|supercharge[sd]?|game.changer|'
    r'unlock(s|ed)?|empower(s|ed)?|delve|leverag(e|es|ed|ing)|(user )?experience|now really|say goodbye|with ease|'
    r'under the hood|we.re (excited|thrilled))\b',
    caseSensitive: false);

/// What's wrong with [notes], one message per problem, with line numbers.
List<String> releaseNoteProblems(String notes) => [
      for (final (i, line) in notes.split('\n').indexed) ...[
        if (RegExp(r'^\s*- \*\*[^*]+[.:!]\*\*').hasMatch(line))
          '${i + 1}: starts with a bold title; start with what changed',
        if (line.trimLeft().startsWith('- ') && line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length - 1 > _maxWords)
          '${i + 1}: over $_maxWords words; one change in a sentence or two',
        for (final m in _filler.allMatches(line)) '${i + 1}: "${m[0]}" sounds like an ad; say what it does',
        if (line.contains('!')) '${i + 1}: no exclamation marks',
        if (line.contains('—')) '${i + 1}: use a comma or a full stop instead of a dash',
      ],
    ];

bool _isChecked(String name) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.md$').firstMatch(name);
  if (m == null) return false;
  for (var i = 0; i < 3; i++) {
    final a = int.parse(m[i + 1]!), b = _checkedAfter[i];
    if (a != b) return a > b;
  }
  return false;
}

void main() {
  test('new release notes read like a person wrote them', () {
    for (final f in Directory('release-notes').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!_isChecked(name)) continue;
      expect(releaseNoteProblems(f.readAsStringSync()), isEmpty, reason: 'release-notes/$name');
    }
  });

  test('the checks catch the habits they are for', () {
    expect(releaseNoteProblems('- **A siddur that knows every line.** Lines are marked.'), hasLength(1));
    expect(releaseNoteProblems('- A seamless new experience!'), hasLength(3));
    expect(releaseNoteProblems('- ${'word ' * 41}'), hasLength(1));
    expect(releaseNoteProblems('- Settings → Customs has Tefillin on Chol HaMoed.\n- Fixed: Morid HaTal showed in the summer.'), isEmpty);
    expect(_isChecked('0.7.0.md'), isFalse);
    expect(_isChecked('0.7.1.md'), isTrue);
    expect(_isChecked('1.0.0.md'), isTrue);
    expect(_isChecked('README.md'), isFalse);
  });
}
