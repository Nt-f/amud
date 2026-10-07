import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../home/card_registry.dart';
import '../home/cards/card_frame.dart';
import '../home/today.dart';
import '../zmanim/zman_catalog.dart';
import 'js_runtime.dart';
import '../../core/l10n.dart';

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

/// Each card's last result, shown while the next minute's run (which may
/// be waiting on the network) is still going.
final _lastJsResult = <String, JsCardResult>{};

/// Storage keys of the cards' saved results.
const savedCardPrefix = 'jsCardLast:';

/// A card's last result that had all its data, kept so the card still shows
/// it offline or after a restart, with when it was made.
typedef SavedCardResult = ({Object? value, DateTime at});

String _scriptHash(String script) => sha1.convert(utf8.encode(script)).toString();

/// The saved result of card [cardId], if it was made by [script].
@visibleForTesting
SavedCardResult? readSavedCard(Storage storage, String cardId, String script) =>
    storage.readJson<SavedCardResult?>('$savedCardPrefix$cardId', (j) {
      final m = (j as Map).cast<String, Object?>();
      if (m['script'] != _scriptHash(script)) return null;
      return (value: m['value'], at: DateTime.parse(m['at'] as String));
    });

/// Saves [value] as card [cardId]'s result: when it changes, and otherwise
/// every ten minutes, so "last updated" stays close without writing every
/// minute.
@visibleForTesting
Future<void> saveCard(Storage storage, String cardId, String script, Object? value, {DateTime? now}) async {
  now ??= DateTime.now();
  final saved = readSavedCard(storage, cardId, script);
  if (saved != null && jsonEncode(saved.value) == jsonEncode(value) && now.difference(saved.at) < const Duration(minutes: 10)) return;
  await storage.writeJson('$savedCardPrefix$cardId', {'script': _scriptHash(script), 'at': now.toIso8601String(), 'value': value});
}

class JsCard extends ConsumerWidget {
  final CardConfig cfg;
  const JsCard(this.cfg, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final script = cfg.setting<String>('script', sampleJsCard);
    final result = ref.watch(_jsResultProvider((script, _contextJson(ref))));
    final last = _lastJsResult['${cfg.id}|$script'];
    final storage = ref.read(storageProvider);
    final saved = readSavedCard(storage, cfg.id, script);
    final title = cfg.setting<String>('title', 'Custom card');
    Widget show(JsCardResult r) => r.ok ? DeclarativeCard(spec: r.value, fallbackTitle: title) : _error(context, r.error!);
    // What it showed when it last had its data, and since when.
    Widget? showSaved() => saved == null
        ? null
        : DeclarativeCard(
            spec: saved.value,
            fallbackTitle: title,
            note: context.tr('Not updated since {time}', {'time': _when(context, saved.at)}),
          );
    return result.when(
      loading: () =>
          (last != null ? show(last) : null) ??
          showSaved() ??
          CardFrame(title: title, icon: Icons.code, child: const LinearProgressIndicator()),
      error: (e, _) => showSaved() ?? _error(context, '$e'),
      data: (r) {
        if (r.ok && !r.fetchFailed) {
          _lastJsResult['${cfg.id}|$script'] = r;
          saveCard(storage, cfg.id, script, r.value);
          return show(r);
        }
        // Offline, or the script failed: what it last showed, if anything.
        return showSaved() ?? show(r);
      },
    );
  }

  /// "14:05" today, or the date and time before that.
  static String _when(BuildContext context, DateTime at) {
    final l = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final time = l.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    return DateUtils.isSameDay(at, now) ? time : '${l.formatShortMonthDay(at)} $time';
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

  /// A small line under the card, such as when it was last updated.
  final String? note;
  const DeclarativeCard({super.key, required this.spec, required this.fallbackTitle, this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = spec is Map ? (spec as Map).cast<String, Object?>() : <String, Object?>{'children': [spec]};
    final hebFont = ref.watch(settingsProvider.select((x) => x.hebrewFont));
    return CardFrame(
      title: (s['title'] as String?) ?? fallbackTitle,
      icon: _icons[s['icon']] ?? Icons.code,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final c in (s['children'] as List?) ?? const []) _node(context, c, hebFont),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.cloud_off, size: 14, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 4),
              Expanded(child: Text(note!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline))),
            ]),
          ),
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
      TextField(controller: _title, decoration: InputDecoration(labelText: context.tr('Title')), onChanged: (_) => _emit()),
      const SizedBox(height: 12),
      TextField(
        controller: _script,
        maxLines: 16,
        minLines: 8,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(labelText: context.tr('Script'), border: OutlineInputBorder(), alignLabelWithHint: true),
        onChanged: (_) => _emit(),
      ),
      const SizedBox(height: 8),
      Row(children: [
        FilledButton.tonalIcon(onPressed: _running ? null : _run, icon: const Icon(Icons.play_arrow), label: Text(context.tr('Run preview'))),
        const SizedBox(width: 8),
        TextButton(onPressed: () => _showApi(context), child: Text(context.tr('API'))),
      ]),
      if (_preview != null) ...[
        const SizedBox(height: 8),
        _preview!.ok
            ? DeclarativeCard(spec: _preview!.value, fallbackTitle: _title.text)
            : Text(_preview!.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
      ],
      const SizedBox(height: 8),
      Text(
        'Scripts run on-device in a sandbox (JavaScriptCore on Apple platforms, QuickJS elsewhere, a Web Worker on web). '
        'They can fetch() https URLs (up to 10 requests, 2 MB each; GETs are cached for 5 minutes) and have 15 seconds in all.',
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
render(ctx) — or async render(ctx) — must return:
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

fetch(url, {method?, headers?, body?}) → Promise of
  {ok, status, statusText, url, headers.get(name), text(), json()}
  https only · at most 10 per update · 2 MB · 10 s each ·
  GET responses cached 5 minutes · on web the server must allow CORS
  Whole script: 15 seconds. The card re-runs every minute.

Full guide: skills/js-card/SKILL.md in the app's repository.
'''),
          ),
        ),
      ),
    );
  }
}
