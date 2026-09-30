import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/settings.dart';
import '../home/card_registry.dart';
import '../home/cards/card_frame.dart';
import '../home/today.dart';
import '../zmanim/zman_catalog.dart';
import 'js_runtime.dart';

const sampleJsCard = r'''// A custom card. Define render(ctx) and return a card description.
// ctx.hebrewDate, ctx.zmanim.sunset.time, ctx.day.roshChodesh, ctx.omerTonight,
// ctx.learning.dafYomi, ctx.parsha.en, ctx.holidays … (see "API" below)
function render(ctx) {
  var z = ctx.zmanim;
  var items = [
    {type: 'text', text: ctx.hebrewDate.he, style: 'hebrew'},
    {type: 'row', children: [
      {type: 'text', text: 'Sunset', style: 'caption'},
      {type: 'spacer'},
      {type: 'text', text: z.sunset.time, style: 'title'}
    ]}
  ];
  if (ctx.day.roshChodesh) items.push({type: 'chip', text: "Ya'aleh VeYavo today", color: 'amber'});
  if (ctx.omerTonight) items.push({type: 'chip', text: 'Omer tonight: ' + ctx.omerTonight});
  return {title: 'My card', icon: 'star', children: items};
}
''';

final jsRuntimeProvider = Provider<JsCardRuntime>((ref) => createJsCardRuntime());

/// Results are keyed by script + minute so cards refresh with the clock
/// without re-running on every rebuild.
final _jsResultProvider = FutureProvider.family<JsCardResult, (String, String)>((ref, args) async {
  final (script, ctx) = args;
  return ref.read(jsRuntimeProvider).render(script, ctx);
});

String _contextJson(WidgetRef ref) {
  final snap = ref.watch(todaySnapshotProvider);
  final names = ref.watch(zmanResolverProvider);
  final m = snap.toJsContext(names);
  // Drop seconds from "now" so the family key changes at most once a minute.
  m['now'] = (m['now'] as String).substring(0, 16);
  return jsonEncode(m);
}

class JsCard extends ConsumerWidget {
  final CardConfig cfg;
  const JsCard(this.cfg, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final script = cfg.setting<String>('script', sampleJsCard);
    final result = ref.watch(_jsResultProvider((script, _contextJson(ref))));
    return result.when(
      loading: () => CardFrame(title: cfg.setting<String>('title', 'Custom card'), icon: Icons.code, child: const LinearProgressIndicator()),
      error: (e, _) => _error(context, '$e'),
      data: (r) => r.ok ? DeclarativeCard(spec: r.value, fallbackTitle: cfg.setting<String>('title', 'Custom card')) : _error(context, r.error!),
    );
  }

  Widget _error(BuildContext context, String e) => CardFrame(
        title: cfg.setting<String>('title', 'Custom card'),
        icon: Icons.error_outline,
        child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12), maxLines: 6),
      );
}

const _icons = <String, IconData>{
  'star': Icons.star_outline,
  'sun': Icons.wb_sunny_outlined,
  'moon': Icons.nights_stay_outlined,
  'book': Icons.menu_book_outlined,
  'clock': Icons.schedule,
  'candle': Icons.local_fire_department_outlined,
  'calendar': Icons.calendar_month,
  'heart': Icons.favorite_outline,
  'info': Icons.info_outline,
  'code': Icons.code,
};

const _colors = <String, Color>{
  'amber': Colors.amber,
  'blue': Colors.blue,
  'green': Colors.green,
  'red': Colors.red,
  'purple': Colors.purple,
  'teal': Colors.teal,
  'grey': Colors.grey,
};

/// Renders the JSON returned by a JS card with native widgets. Only this
/// fixed vocabulary is supported — scripts cannot create arbitrary UI.
class DeclarativeCard extends ConsumerWidget {
  final Object? spec;
  final String fallbackTitle;
  const DeclarativeCard({super.key, required this.spec, required this.fallbackTitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = spec is Map ? (spec as Map).cast<String, Object?>() : <String, Object?>{'children': [spec]};
    final hebFont = ref.watch(settingsProvider.select((x) => x.hebrewFont));
    return CardFrame(
      title: (s['title'] as String?) ?? fallbackTitle,
      icon: _icons[s['icon']] ?? Icons.code,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final c in (s['children'] as List?) ?? const []) _node(context, c, hebFont),
      ]),
    );
  }

  Widget _node(BuildContext context, Object? n, String hebFont, [int depth = 0]) {
    if (depth > 8) return const SizedBox.shrink();
    final theme = Theme.of(context);
    if (n is String || n is num) return Text('$n');
    if (n is! Map) return const SizedBox.shrink();
    final m = n.cast<String, Object?>();
    final color = _colors[m['color']];
    List<Widget> kids() => [for (final c in (m['children'] as List?) ?? const []) _node(context, c, hebFont, depth + 1)];
    switch (m['type']) {
      case 'text':
        final text = '${m['text'] ?? ''}';
        final rtl = RegExp('[֐-׿]').hasMatch(text);
        final style = switch (m['style']) {
          'title' => theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          'headline' => theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          'caption' => theme.textTheme.bodySmall,
          'hebrew' => theme.textTheme.titleLarge?.copyWith(fontFamily: hebFont),
          _ => theme.textTheme.bodyMedium,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(text, style: style?.copyWith(color: color), textDirection: rtl ? TextDirection.rtl : null),
        );
      case 'row':
        return Row(children: kids().map((w) => w is Spacer ? w : Flexible(child: w)).toList());
      case 'column':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids());
      case 'chip':
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Chip(label: Text('${m['text'] ?? ''}'), backgroundColor: color?.withValues(alpha: 0.25), visualDensity: VisualDensity.compact),
        );
      case 'progress':
        final v = (m['value'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0;
        return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: LinearProgressIndicator(value: v, color: color));
      case 'divider':
        return const Divider();
      case 'spacer':
        return const Spacer();
      default:
        return const SizedBox.shrink();
    }
  }
}

class JsCardEditor extends ConsumerStatefulWidget {
  final CardConfig cfg;
  final ValueChanged<CardConfig> onChanged;
  const JsCardEditor({super.key, required this.cfg, required this.onChanged});

  @override
  ConsumerState<JsCardEditor> createState() => _JsCardEditorState();
}

class _JsCardEditorState extends ConsumerState<JsCardEditor> {
  late final _title = TextEditingController(text: widget.cfg.setting<String>('title', 'My card'));
  late final _script = TextEditingController(text: widget.cfg.setting<String>('script', sampleJsCard));
  JsCardResult? _preview;
  bool _running = false;

  void _emit() => widget.onChanged(
      widget.cfg.copyWith(settings: {...widget.cfg.settings, 'title': _title.text, 'script': _script.text}));

  Future<void> _run() async {
    setState(() => _running = true);
    final r = await ref.read(jsRuntimeProvider).render(_script.text, _contextJson(ref));
    if (mounted) setState(() => (_preview = r, _running = false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title'), onChanged: (_) => _emit()),
      const SizedBox(height: 12),
      TextField(
        controller: _script,
        maxLines: 16,
        minLines: 8,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration(labelText: 'Script', border: OutlineInputBorder(), alignLabelWithHint: true),
        onChanged: (_) => _emit(),
      ),
      const SizedBox(height: 8),
      Row(children: [
        FilledButton.tonalIcon(onPressed: _running ? null : _run, icon: const Icon(Icons.play_arrow), label: const Text('Run preview')),
        const SizedBox(width: 8),
        TextButton(onPressed: () => _showApi(context), child: const Text('API')),
      ]),
      if (_preview != null) ...[
        const SizedBox(height: 8),
        _preview!.ok
            ? DeclarativeCard(spec: _preview!.value, fallbackTitle: _title.text)
            : Text(_preview!.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
      ],
      const SizedBox(height: 8),
      Text(
        'Scripts run on-device in a sandbox (JavaScriptCore on Apple platforms, QuickJS elsewhere, a Web Worker on web) '
        'with no network access and a 2-second limit.',
        style: theme.textTheme.bodySmall,
      ),
    ]);
  }

  void _showApi(BuildContext context) {
    final vars = DayContext.variableDocs.entries.map((e) => '  ctx.day.${e.key} — ${e.value}').join('\n');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.8,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText('''
render(ctx) must return:
  { title?, icon?: star|sun|moon|book|clock|candle|calendar|heart|info, children: [node…] }
node:
  {type:'text', text, style?: title|headline|caption|hebrew, color?}
  {type:'row'|'column', children:[…]}   {type:'chip', text, color?}
  {type:'progress', value:0..1}   {type:'divider'}   {type:'spacer'}
colors: amber blue green red purple teal grey

ctx:
  ctx.now (UTC ISO), ctx.gregorian (YYYY-MM-DD), ctx.afterSunset
  ctx.hebrewDate {day, month, monthName, year, en, he, heNikud}
  ctx.location {name, latitude, longitude, elevation, tzid, il}
  ctx.holidays [{en, he, emoji}]   ctx.parsha {en, he}   ctx.omerTonight
  ctx.zmanim.<key> {time 'HH:MM', iso, name, he}
     keys: ${builtInZmanim.map((z) => z.key).join(', ')}, custom:<id>
  ctx.learning.<schedule> (English), ctx.learningHe.<schedule>
  ctx.day.* — halachic day flags:
$vars
'''),
          ),
        ),
      ),
    );
  }
}
