import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/text_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long press offers Report and requires issue details', (tester) async {
    var selectedText = '';
    // The dialog reads the report Worker's address from storage.
    late Storage storage;
    await tester.runAsync(() async => storage = await Storage.openAt(Directory.systemTemp.createTempSync('report').path));
    await tester.pumpWidget(ProviderScope(overrides: [storageProvider.overrideWithValue(storage)], child: MaterialApp(home: Scaffold(
      body: SelectionArea(
        onSelectionChanged: (selection) => selectedText = selection?.plainText ?? '',
        contextMenuBuilder: (context, state) => textReportMenu(context, state,
            selectedText: selectedText, location: 'Siddur / Morning prayer'),
        child: const Center(child: Text('Prayer text to report')),
      ),
    ))));
    await tester.longPress(find.text('Prayer text to report'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report a text issue'), findsOneWidget);
    expect(find.text('Siddur / Morning prayer'), findsOneWidget);
    expect(selectedText, isNotEmpty);
    // Reports go to the default Worker, so the button sends.
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(find.text('Please describe the issue.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Report a text issue'), findsNothing);
  });
}
