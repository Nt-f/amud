import 'package:amud/core/adaptive.dart';
import 'package:amud/core/keypad.dart';
import 'package:amud/core/l10n.dart';
import 'dart:io';

import 'package:amud/core/providers.dart';
import 'package:amud/core/settings.dart';
import 'package:amud/core/storage.dart';
import 'package:amud/features/setup/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A flip phone's screen: 240 by 320.
void _flip(WidgetTester t, {double scale = 1}) {
  t.view.physicalSize = const Size(240, 320);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget home, {VoidCallback? onMenu, VoidCallback? onBack, UiLanguage lang = UiLanguage.en}) => ProviderScope(
      overrides: [keypadModeProvider.overrideWithValue(true)],
      child: MaterialApp(
        builder: (c, child) => AppText(
          lang: lang,
          ashkenazi: false,
          child: KeypadLayer(onMenu: onMenu ?? () {}, onBack: onBack ?? () {}, child: child!),
        ),
        home: home,
      ),
    );

/// Opens [app] and lets the page take focus, as a phone shows it.
Future<void> _open(WidgetTester t, Widget app) async {
  await t.pumpWidget(app);
  await t.pumpAndSettle();
}

Future<void> _press(WidgetTester t, LogicalKeyboardKey key, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await t.sendKeyEvent(key);
    await t.pumpAndSettle();
  }
}

bool _focused(WidgetTester t, String text) => Focus.of(t.element(find.text(text))).hasPrimaryFocus;

void main() {
  testWidgets('down reaches the end of a list that builds as it scrolls', (t) async {
    _flip(t);
    await _open(t, _app(Scaffold(
      body: ListView.builder(
        itemCount: 40,
        itemBuilder: (c, i) => ListTile(title: Text('Item $i'), onTap: () {}),
      ),
    )));
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(_focused(t, 'Item 0'), isTrue);
    await _press(t, LogicalKeyboardKey.arrowDown, 60);
    expect(_focused(t, 'Item 39'), isTrue);
    await _press(t, LogicalKeyboardKey.arrowUp, 60);
    expect(_focused(t, 'Item 0'), isTrue);
  });

  testWidgets('a page of text with nothing to press scrolls', (t) async {
    _flip(t);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _open(t, _app(Scaffold(
      body: ListView(controller: scroll, children: [for (var i = 0; i < 30; i++) SizedBox(height: 50, child: Text('Line $i'))]),
    )));
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(scroll.offset, greaterThan(0));
    await _press(t, LogicalKeyboardKey.arrowDown, 40);
    expect(scroll.offset, scroll.position.maxScrollExtent);
    await _press(t, LogicalKeyboardKey.arrowUp, 40);
    expect(scroll.offset, 0);
  });

  testWidgets('up and down leave a search box rather than stay in it', (t) async {
    _flip(t);
    await _open(t, _app(Scaffold(
      body: ListView(children: [
        const TextField(decoration: InputDecoration(hintText: 'Search')),
        for (var i = 0; i < 3; i++) ListTile(title: Text('Item $i'), onTap: () {}),
      ]),
    )));
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNotNull);
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(_focused(t, 'Item 0'), isTrue);
    await _press(t, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNotNull);
  });

  testWidgets('from a button in the app bar, down scrolls the page under it', (t) async {
    _flip(t);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _open(t, _app(Scaffold(
      appBar: AppBar(title: const Text('Shacharis'), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.text_fields))]),
      body: ListView(controller: scroll, children: [for (var i = 0; i < 30; i++) SizedBox(height: 50, child: Text('Line $i'))]),
    )));
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()), reason: 'the button has focus');
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets("a reader's text, selectable, scrolls when it has focus", (t) async {
    _flip(t);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _open(t, _app(Scaffold(
      body: SelectionArea(
        child: ListView(controller: scroll, children: [
          for (var i = 0; i < 30; i++) i == 3 ? ListTile(title: const Text('Psalm 1'), onTap: () {}) : SizedBox(height: 50, child: Text('Verse $i')),
        ]),
      ),
    )));
    // The selection area's own focus, as a reader's first d-pad press gives it.
    Focus.of(t.element(find.text('Verse 0'))).requestFocus();
    await t.pump();
    await _press(t, LogicalKeyboardKey.arrowDown, 2);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('an item taller than the screen is read through before focus moves on', (t) async {
    _flip(t);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _open(t, _app(Scaffold(
      body: ListView(controller: scroll, children: [
        ListTile(title: const Text('A'), onTap: () {}),
        InkWell(onTap: () {}, child: const SizedBox(height: 900, child: Align(alignment: Alignment.topLeft, child: Text('Tall')))),
        ListTile(title: const Text('B'), onTap: () {}),
      ]),
    )));
    await _press(t, LogicalKeyboardKey.arrowDown, 2);
    expect(_focused(t, 'Tall'), isTrue);
    final before = scroll.offset;
    await _press(t, LogicalKeyboardKey.arrowDown);
    expect(_focused(t, 'Tall'), isTrue, reason: 'the rest of it is still below');
    expect(scroll.offset, greaterThan(before));
    await _press(t, LogicalKeyboardKey.arrowDown, 10);
    expect(_focused(t, 'B'), isTrue);
  });

  testWidgets('the soft keys open the menu and go back, and the bar names them', (t) async {
    _flip(t);
    var menus = 0, backs = 0;
    await _open(t, _app(const Scaffold(body: Text('Page')), onMenu: () => menus++, onBack: () => backs++));
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    await _press(t, LogicalKeyboardKey.contextMenu);
    expect(menus, 1);
    await _press(t, LogicalKeyboardKey.escape);
    expect(backs, 1);
  });

  testWidgets('a keypad menu focuses its first item and runs the one picked', (t) async {
    _flip(t);
    String? picked;
    await _open(t, _app(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showKeypadMenu(context, 'Shacharis', [
            for (final l in ['Focus mode', 'Larger text', 'Smaller text', 'Text settings', 'Date', 'Why today?'])
              KeypadMenuItem(l, () => picked = l, icon: Icons.circle, key: '#'),
          ]),
          child: const Text('Open'),
        ),
      ),
    )));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(_focused(t, 'Focus mode'), isTrue);
    await _press(t, LogicalKeyboardKey.arrowDown, 5);
    expect(_focused(t, 'Why today?'), isTrue);
    await _press(t, LogicalKeyboardKey.select);
    expect(picked, 'Why today?');
  });

  testWidgets('the soft-key bar fits a 240dp screen in Yiddish at 1.3× text', (t) async {
    _flip(t, scale: 1.3);
    await _open(t, _app(const Scaffold(body: SizedBox()), lang: UiLanguage.yi));
    expect(t.takeException(), isNull);
    expect(find.text('מעניו'), findsOneWidget);
    expect(find.text('אויסקלייבן'), findsOneWidget);
  });

  testWidgets('first run: setup is answered and left by keys alone', (t) async {
    _flip(t);
    late Storage storage;
    await t.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('keypad');
      addTearDown(() => dir.delete(recursive: true));
      storage = await Storage.openAt(dir.path, name: 'keypad');
    });
    final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage), keypadModeProvider.overrideWithValue(true)]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        builder: (context, child) => KeypadLayer(onMenu: () {}, onBack: () {}, child: child!),
        home: const SetupScreen(),
      ),
    ));
    await t.pumpAndSettle();
    bool inChoice() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ChoiceBar<UiLanguage>>() != null;
    bool onNext() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FilledButton>() != null;
    // The language: down to its choices (past Skip, at the top), on to
    // Hebrew (on the next line, at this width), and pick it.
    for (var i = 0; i < 4 && !inChoice(); i++) {
      await _press(t, LogicalKeyboardKey.arrowDown);
    }
    expect(inChoice(), isTrue);
    await _press(t, LogicalKeyboardKey.arrowDown);
    await _press(t, LogicalKeyboardKey.select);
    expect(c.read(settingsProvider).uiLanguage, UiLanguage.he);
    // Down past the options to Next, at the bottom, and on to the next page.
    for (var i = 0; i < 8 && !onNext(); i++) {
      await _press(t, LogicalKeyboardKey.arrowDown);
    }
    expect(onNext(), isTrue);
    await _press(t, LogicalKeyboardKey.select);
    expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget, reason: 'on page two, with Back beside Next');
    expect(t.takeException(), isNull);
  });

  test('keypad navigation is saved, and defaults to automatic', () {
    expect(const AppSettings().keypadNav, KeypadNav.auto);
    final json = const AppSettings(keypadNav: KeypadNav.on).toJson();
    expect(AppSettings.fromJson(json).keypadNav, KeypadNav.on);
    expect(AppSettings.fromJson({...json, 'keypadNav': 'bogus'}).keypadNav, KeypadNav.auto);
  });
}
