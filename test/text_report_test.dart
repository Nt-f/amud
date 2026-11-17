import 'dart:convert';
import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/core/text_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('a report says which build sent it', () async {
    PackageInfo.setMockInitialValues(
        appName: 'Amud', packageName: 'page.amud', version: '0.14.0', buildNumber: '10', buildSignature: '');
    // CI builds pass --dart-define=GIT_COMMIT=<sha>; tests usually don't.
    const commit = String.fromEnvironment('GIT_COMMIT');
    final build = commit.isEmpty ? 'amud 0.14.0+10' : 'amud 0.14.0+10 ${commit.substring(0, 10)}';
    expect(await appBuild(), build);
    late http.Request sent;
    await sendReport('https://worker.example/', 'a' * 32, {'location': 'here', 'app': await appBuild()},
        client: MockClient((r) async {
      sent = r;
      return http.Response('{}', 200);
    }));
    expect(sent.url.toString(), 'https://worker.example/v1/report');
    expect(jsonDecode(sent.body), {'uid': 'a' * 32, 'location': 'here', 'app': build});
  });

  testWidgets('long press offers Report and requires issue details', (tester) async {
    var selectedText = '';
    // The dialog reads the report Worker's address from storage.
    late Storage storage;
    await tester.runAsync(() async => storage = await Storage.openAt(Directory.systemTemp.createTempSync('report').path));
    await tester.pumpWidget(ProviderScope(overrides: [storageProvider.overrideWithValue(storage)], child: MaterialApp(home: Scaffold(
      body: SelectionArea(
        onSelectionChanged: (selection) => selectedText = selection?.plainText ?? '',
        contextMenuBuilder: (context, state) => textReportMenu(context, state,
            selectedText: selectedText,
            place: () => (label: 'Siddur / Morning prayer', location: 'Siddur Ashkenaz › Weekday/Shacharit/Modeh Ani he 1')),
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
    // The short label is shown; the full location is what's sent.
    expect(find.text('Siddur / Morning prayer'), findsOneWidget);
    expect(tester.widget<TextReportDialog>(find.byType(TextReportDialog)).location,
        'Siddur Ashkenaz › Weekday/Shacharit/Modeh Ani he 1');
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
