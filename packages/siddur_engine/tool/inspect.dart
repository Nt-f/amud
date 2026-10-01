// Debug CLI: prints how a section resolves on a given Hebrew date.
//   dart run tool/inspect.dart "Siddur Ashkenaz" "Weekday/Shacharit/Amidah" 5786 7 30
import 'dart:convert';
import 'dart:io';

import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

class _FileSource implements TextSource {
  final String root;
  _FileSource(this.root);
  @override
  Future<List<int>> readBytes(String file) => File('$root/$file').readAsBytes();
}

Future<void> main(List<String> args) async {
  initHebcal();
  final lib = SiddurLibrary(_FileSource('../..'), gzip.decode);
  final m = await lib.manifest();
  final book = m.book(args[0])!;
  final root = await lib.index(book);
  final node = root.find(args[1])!;
  final hd = HDate(int.parse(args[4]), int.parse(args[3]), int.parse(args[2]));
  final il = args.length > 5 && args[5] == 'il';
  final heVersions = [for (final v in book.byLanguage('he')) await lib.version(v)];
  final enVersions = [for (final v in book.byLanguage('en').where((v) => v.languageTag == null)) await lib.version(v)];
  final sel = VersionSelection(heVersions, enVersions);
  final rulesJson = jsonDecode(File('../../assets/rules/rules.json').readAsStringSync()) as Map<String, dynamic>;
  final res = SiddurResolver().withOverrides((rulesJson[book.title] as Map<String, dynamic>?) ?? const {});
  final ctxs = <Service, DayContext>{};
  final items = res.resolve(node, sel,
      (s) => ctxs.putIfAbsent(s, () => DayContext.forService(hd, s, il: il)),
      options: const ResolveOptions(showNotes: true));
  print('Date: $hd  ${ctxs.values.first.labels}');
  String short(String s) {
    final p = stripHtml(s).replaceAll('\n', ' ');
    return p.length > 70 ? '${p.substring(0, 70)}…' : p;
  }

  for (final it in items) {
    switch (it) {
      case HeadingItem h:
        print('${'  ' * h.level}# ${h.node.en} [${h.applicability.name}${h.labelEn != null ? ' ${h.labelEn}' : ''}]');
      case CollapsedSectionItem c:
        print('  [COLLAPSED] ${c.node.en} (${c.labelEn})');
      case InsertedSectionItem ins:
        print('  >>> INSERTED ${ins.node.id} (${ins.labelEn})');
      case ExcludedGroupItem g:
        print('    [${g.items.length} lines not said: ${g.labelsEn.take(3).join(', ')}]');
      case DynamicItem d:
        print('  [DYNAMIC ${d.kind}] ${d.data['he']} | ${d.data['en']}');
      case SegmentItem s:
        final tag = s.applicability == Applicability.always ? '' : '{${s.applicability.name}: ${s.labelEn}} ';
        final runs = (s.he ?? s.tr)!.runs.where((r) => r.applicability != Applicability.always);
        final inline = runs.isEmpty ? '' : ' <<${runs.map((r) => '${r.applicability.name}:${r.labelEn}').join(', ')}>>';
        print('    ${s.chazarah ? '[chazarah] ' : ''}${s.kind.name.substring(0, 3)} $tag${short((s.he ?? s.tr)!.segment.html)}$inline');
    }
  }
}
