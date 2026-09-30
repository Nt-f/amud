import 'package:flutter/material.dart';
import 'package:flutter_siddur/core/split_row.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double width, TextDirection dir) => Directionality(
      textDirection: dir,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: const SplitRow(children: [
            SizedBox(key: Key('a'), width: 100, height: 20),
            SizedBox(key: Key('b'), width: 80, height: 30),
          ]),
        ),
      ),
    );

void main() {
  testWidgets('side by side when it fits', (t) async {
    await t.pumpWidget(_host(300, TextDirection.ltr));
    expect(t.getTopLeft(find.byKey(const Key('a'))), const Offset(0, 10));
    expect(t.getTopLeft(find.byKey(const Key('b'))), const Offset(220, 0));
  });

  testWidgets('stacks, end-aligned, when it does not', (t) async {
    await t.pumpWidget(_host(150, TextDirection.ltr));
    expect(t.getTopLeft(find.byKey(const Key('a'))), Offset.zero);
    expect(t.getTopLeft(find.byKey(const Key('b'))), const Offset(70, 22));
    expect(t.getSize(find.byType(SplitRow)).height, 52);
  });

  testWidgets('mirrors in RTL', (t) async {
    await t.pumpWidget(_host(300, TextDirection.rtl));
    expect(t.getTopLeft(find.byKey(const Key('a'))), const Offset(200, 10));
    expect(t.getTopLeft(find.byKey(const Key('b'))), const Offset(0, 0));
  });
}
