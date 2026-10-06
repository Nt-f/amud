/// Choices the reader makes inside the text ("whose table did you eat
/// at?", "is this a bris or a wedding?"): a segment with `select: "<id>"` in
/// the corpus draws the selector, and the picked option answers the `if_…`
/// conditions that follow it.
class ReaderChoice {
  final String id;

  /// English label shown above the options, if any.
  final String? title;

  /// Options as (key, English label, the `if_…` conditions it makes true).
  final List<(String, String, List<String>)> options;
  const ReaderChoice(this.id, this.options, {this.title});

  String get defaultKey => options.first.$1;

  /// Every condition any option answers.
  Set<String> get conditions => {for (final o in options) ...o.$3};
}

const readerChoices = {
  'table': ReaderChoice('table', [
    ('own', 'My own table', ['if_eatingAtOwnTable']),
    ('parents', "My parents' table", ['if_eatingAtParentsTable']),
    ('guest', "Someone else's table", ['if_guest']),
  ]),
  'occasion': ReaderChoice(
    'occasion',
    [
      ('none', 'None', []),
      ('bris', 'Bris', ['if_festiveMeal', 'if_bris']),
      ('wedding', 'Wedding / Sheva Berachos', ['if_festiveMeal', 'if_wedding']),
      ('pidyon', 'Pidyon HaBen', ['if_festiveMeal', 'if_pidyonHaben']),
    ],
    title: 'Special occasion',
  ),
};

/// The `if_…` answers for what the reader picked: the picked option's
/// conditions are true and every other condition of the choice false.
Map<String, bool> choiceAnswers(Map<String, String> picked) {
  final out = <String, bool>{};
  for (final c in readerChoices.values) {
    final key = picked[c.id] ?? c.defaultKey;
    final on = {for (final o in c.options) if (o.$1 == key) ...o.$3};
    for (final id in c.conditions) {
      out[id] = on.contains(id);
    }
  }
  return out;
}
