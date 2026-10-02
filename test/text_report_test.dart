import 'package:amud/core/text_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long press offers Report and requires issue details', (tester) async {
    var selectedText = '';
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SelectionArea(
        onSelectionChanged: (selection) => selectedText = selection?.plainText ?? '',
        contextMenuBuilder: (context, state) => textReportMenu(context, state,
            selectedText: selectedText, location: 'Siddur / Morning prayer'),
        child: const Center(child: Text('Prayer text to report')),
      ),
    )));
    await tester.longPress(find.text('Prayer text to report'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report a text issue'), findsOneWidget);
    expect(find.text('Siddur / Morning prayer'), findsOneWidget);
    expect(selectedText, isNotEmpty);
    await tester.tap(find.text('Continue to GitHub'));
    await tester.pumpAndSettle();
    expect(find.text('Please describe the issue.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Report a text issue'), findsNothing);
  });
}
