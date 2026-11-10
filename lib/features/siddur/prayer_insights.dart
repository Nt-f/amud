import 'package:siddur_engine/siddur_engine.dart';

/// Shows the actual variables used by a rule, including unknown custom ones.
List<String> conditionFacts(String expression, DayContext day) => [
  for (final key in Condition.parse(expression).identifiers)
    '${DayContext.variableDocs[key] ?? key}: ${switch (day.env[key]) {
      true => 'Yes',
      false => 'No',
      null => 'Unknown',
      final value => value.toString(),
    }}',
];

String resolvedText(ResolvedSegment? segment) => segment == null
    ? ''
    : stripHtml(
        segment.runs
            .where(
              (r) => !r.marker && r.applicability != Applicability.notToday,
            )
            .map((r) => r.html)
            .join(''),
      ).trim();
