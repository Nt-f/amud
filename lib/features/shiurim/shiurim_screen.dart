import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import 'shiurim_data.dart';
import 'shiurim_settings.dart';

const _flOz = 29.5735295625;

/// "86", "2.9", "0.024", "1,154": enough digits to be useful, no more.
String formatAmount(double v) {
  final a = v.abs();
  if (a == 0) return '0';
  if (a >= 1000) {
    final s = v.round().toString();
    return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  }
  final digits = a >= 100
      ? 0
      : a >= 10
          ? 1
          : a >= 1
              ? 2
              : (3 - (a.toString().indexOf(RegExp('[1-9]')) - 1)).clamp(3, 8);
  var s = v.toStringAsFixed(digits);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

/// A ruling's value, metric first and then imperial.
String formatRuling(BuildContext context, double value, String unit) => switch (unit) {
      'ml' => '${formatAmount(value)} ml · ${formatAmount(value / _flOz)} fl oz',
      'cm' => '${formatAmount(value)} cm · ${formatAmount(value / 2.54)} in',
      'm' => '${formatAmount(value)} m · ${formatAmount(value / 0.3048)} ft',
      'min' => value == value.roundToDouble()
          ? context.tr('{n} min', {'n': formatAmount(value)})
          : context.tr('{m} min {s} s', {'m': value.floor(), 's': ((value - value.floor()) * 60).round()}),
      _ => '${formatAmount(value)} $unit',
    };

String _name(BuildContext context, String en, String he) => context.uiLanguage == UiLanguage.en ? en : he;

/// Shows where a figure comes from.
void showSource(BuildContext context, String title, String source) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(source, textDirection: TextDirection.ltr),
          ]),
        ),
      ),
    );

/// The shiurim: the common ones by each posek, a converter for every unit,
/// and where each figure comes from. Works offline.
class ShiurimScreen extends ConsumerStatefulWidget {
  const ShiurimScreen({super.key});

  @override
  ConsumerState<ShiurimScreen> createState() => _ShiurimScreenState();
}

class _ShiurimScreenState extends ConsumerState<ShiurimScreen> {
  bool _converter = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(shiurimSettingsProvider);
    final followed = length.opinions!.firstWhere((o) => o.id == s.follow);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Shiurim')),
        actions: [
          IconButton(
            tooltip: context.tr('Where these come from'),
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShiurimSourcesScreen())),
          ),
          IconButton(tooltip: context.tr('Settings'), icon: const Icon(Icons.tune), onPressed: () => _showSettings(context)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(context.tr('Common shiurim')), icon: const Icon(Icons.star_outline)),
            ButtonSegment(value: true, label: Text(context.tr('Converter')), icon: const Icon(Icons.swap_horiz)),
          ],
          selected: {_converter},
          onSelectionChanged: (v) => setState(() => _converter = v.first),
        ),
        const SizedBox(height: 8),
        ActionChip(
          avatar: const Icon(Icons.person_outline, size: 18),
          label: Text(context.tr('Following {name}', {'name': _name(context, followed.en, followed.he)})),
          onPressed: () => _showSettings(context),
        ),
        const SizedBox(height: 4),
        if (_converter) const ShiurimConverter() else for (final c in commonShiurim) _CommonShiurCard(c),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
          child: Text(context.tr('These are published opinions, for reference. Ask your rav how to act.'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }
}

/// A common shiur: the leading ruling large, and every posek's below,
/// each with its source.
class _CommonShiurCard extends ConsumerWidget {
  final CommonShiur shiur;
  const _CommonShiurCard(this.shiur);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shiurimSettingsProvider);
    final lead = s.leading(shiur);
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Text(_name(context, shiur.en, shiur.he), style: theme.textTheme.titleMedium),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatRuling(context, lead.value, lead.unit),
              style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
          Text('${_name(context, lead.en, lead.he)} · ${context.tr(shiur.use)}', style: theme.textTheme.bodySmall),
        ]),
        children: [
          for (final r in shiur.rulings)
            ListTile(
              dense: true,
              leading: Icon(r == lead ? Icons.check_circle : Icons.circle_outlined, size: 18, color: r == lead ? theme.colorScheme.primary : null),
              title: Text(_name(context, r.en, r.he)),
              subtitle: Text(formatRuling(context, r.value, r.unit)),
              trailing: const Icon(Icons.info_outline, size: 18),
              onTap: () => showSource(context, _name(context, r.en, r.he), r.source),
            ),
        ],
      ),
    );
  }
}

/// Converts any amount between any two units of a measure, by the opinion
/// chosen, and shows the result by every other opinion too.
class ShiurimConverter extends ConsumerStatefulWidget {
  const ShiurimConverter({super.key});

  @override
  ConsumerState<ShiurimConverter> createState() => _ConverterState();
}

const _defaultUnits = {
  'length': ('amah', 'cm'),
  'area': ('amahSq', 'm2'),
  'volume': ('reviis', 'ml'),
  'coins': ('perutah', 'g'),
  'time': ('mil', 'min'),
};

class _ConverterState extends ConsumerState<ShiurimConverter> {
  Measure _measure = length;
  final _amount = TextEditingController(text: '1');
  String _from = 'amah', _to = 'cm';
  String? _opinion;
  final _unitOpinions = <String, String>{};

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _pick(Measure m) => setState(() {
        final (from, to) = _defaultUnits[m.id]!;
        _measure = m;
        _from = from;
        _to = to;
        _opinion = null;
      });

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(shiurimSettingsProvider);
    final theme = Theme.of(context);
    final m = _measure;
    final from = m.unit(_from), to = m.unit(_to);
    final amount = double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
    final opinion = m.opinion(_opinion) == null ? null : (_opinion == null ? s.opinionFor(m) : m.opinion(_opinion));
    final unitOpinions = {
      for (final u in [from, to])
        if (u.opinions != null) u.id: _unitOpinions[u.id] ?? s.unitOpinion(u.id),
    };
    double result(Opinion? o, [Map<String, String>? uo]) =>
        convert(m, amount, from, to, opinion: o, unitOpinions: uo ?? unitOpinions);
    final usesOpinion = m.opinions != null && (from.biblical || to.biblical) && from.opinions == null && to.opinions == null;
    // The unit whose own opinions decide the result (walking a mil, say).
    final timed = [from, to].where((u) => u.opinions != null).firstOrNull;

    String unitName(ShiurUnit u) => u.biblical ? _name(context, u.en, u.he) : context.tr(u.en);
    DropdownMenuItem<String> item(ShiurUnit u) => DropdownMenuItem(value: u.id, child: Text(unitName(u), overflow: TextOverflow.ellipsis));
    String money(double grams) =>
        s.silverPerGram == null ? '' : ' · ≈ ${s.currency}${formatAmount(grams * s.silverPerGram!)}';
    String show(double v) {
      final grams = m.id == 'coins' ? v * to.size * (to.biblical ? (opinion?.value ?? 0) : 1) : 0.0;
      return '${formatAmount(v)} ${unitName(to)}${m.id == 'coins' ? money(grams) : ''}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in measures)
          ChoiceChip(label: Text(_name(context, x.en, x.he)), selected: x == m, onSelected: (_) => _pick(x)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: context.tr('Amount'), border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('from-${m.id}-$_from'),
            initialValue: _from,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('From'), border: const OutlineInputBorder()),
            items: [for (final u in m.units) item(u)],
            onChanged: (v) => setState(() => _from = v!),
          ),
        ),
        IconButton(
          tooltip: context.tr('Swap'),
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => setState(() {
            final from = _from;
            _from = _to;
            _to = from;
          }),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('to-${m.id}-$_to'),
            initialValue: _to,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('To'), border: const OutlineInputBorder()),
            items: [for (final u in m.units) item(u)],
            onChanged: (v) => setState(() => _to = v!),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(show(result(opinion)),
                style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
            if (usesOpinion && opinion != null)
              Text(context.tr('According to {name}', {'name': _name(context, opinion.en, opinion.he)}),
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
            if (timed != null)
              Text(context.tr('According to {name}', {'name': _name(context, timed.opinions!.firstWhere((o) => o.id == unitOpinions[timed.id]).en,
                  timed.opinions!.firstWhere((o) => o.id == unitOpinions[timed.id]).he)}),
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
          ]),
        ),
      ),
      // Every opinion, so they can be compared; tap one to use it, or to
      // see its source.
      if (usesOpinion)
        for (final o in m.opinions!)
          ListTile(
            dense: true,
            leading: Icon(o.id == opinion?.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: o.id == opinion?.id ? theme.colorScheme.primary : null),
            title: Text(_name(context, o.en, o.he)),
            subtitle: Text([
              show(result(o)),
              if (o.stringent != null)
                context.tr('stringently {value}', {'value': formatAmount(convert(m, amount, from, to, opinion: Opinion(o.id, o.en, o.he, o.stringent!, source: '')))}),
            ].join(' · ')),
            trailing: IconButton(
              tooltip: context.tr('Source'),
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => showSource(context, _name(context, o.en, o.he), o.source),
            ),
            onTap: () => setState(() => _opinion = o.id),
          ),
      if (timed != null)
        for (final o in timed.opinions!)
          ListTile(
            dense: true,
            leading: Icon(o.id == unitOpinions[timed.id] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: o.id == unitOpinions[timed.id] ? theme.colorScheme.primary : null),
            title: Text(_name(context, o.en, o.he)),
            subtitle: Text(show(result(null, {...unitOpinions, timed.id: o.id}))),
            trailing: IconButton(
              tooltip: context.tr('Source'),
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => showSource(context, _name(context, o.en, o.he), o.source),
            ),
            onTap: () => setState(() => _unitOpinions[timed.id] = o.id),
          ),
      if (!usesOpinion && timed == null && m.opinions != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(context.tr('Both units are fixed, so every opinion gives the same result.'), style: theme.textTheme.bodySmall),
        ),
    ]);
  }
}

Future<void> _showSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ShiurimSettingsSheet(),
    );

class _ShiurimSettingsSheet extends ConsumerWidget {
  const _ShiurimSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shiurimSettingsProvider);
    final n = ref.read(shiurimSettingsProvider.notifier);
    final theme = Theme.of(context);
    Widget choose(String title, String value, List<Opinion> options, void Function(String) set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(title, style: theme.textTheme.titleSmall)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in options)
                ChoiceChip(label: Text(_name(context, o.en, o.he)), selected: o.id == value, onSelected: (_) => set(o.id)),
            ]),
          ],
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(context.tr('Shiurim'), style: theme.textTheme.titleLarge),
          Text(context.tr('Every opinion is always shown. These choose which one leads.'), style: theme.textTheme.bodySmall),
          choose(context.tr('Follow'), s.follow, [for (final o in length.opinions!) if (followable.contains(o.id)) o],
              (v) => n.update((x) => x.copyWith(follow: v))),
          choose(context.tr('Hiluch mil'), s.mil, hiluchMil, (v) => n.update((x) => x.copyWith(mil: v))),
          choose(context.tr("K'dei achilas pras"), s.pras, achilasPras, (v) => n.update((x) => x.copyWith(pras: v))),
          choose(context.tr('Perutah'), s.coins, coins.opinions!, (v) => n.update((x) => x.copyWith(coins: v))),
          Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(context.tr('Price of silver'), style: theme.textTheme.titleSmall)),
          Row(children: [
            SizedBox(
              width: 72,
              child: TextFormField(
                initialValue: s.currency,
                decoration: InputDecoration(labelText: context.tr('Currency'), border: const OutlineInputBorder()),
                onChanged: (v) => n.update((x) => x.copyWith(currency: v.trim())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: s.silverPerGram == null ? '' : formatAmount(s.silverPerGram!),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: context.tr('Per gram'), border: const OutlineInputBorder()),
                onChanged: (v) => n.update((x) => x.copyWith(silverPerGram: () => double.tryParse(v.replaceAll(',', '')))),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.tr("To show coins in money. Enter today's price; the app doesn't look it up, so it works offline."),
                style: theme.textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
}

/// Where every figure comes from: how each measure's units relate, each
/// posek's figure and source, and how the defaults are chosen.
class ShiurimSourcesScreen extends StatelessWidget {
  const ShiurimSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(t, style: theme.textTheme.titleMedium));
    Widget para(String t) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text(t, textDirection: TextDirection.ltr, style: theme.textTheme.bodyMedium));
    Widget source(String name, String text) => ListTile(
          dense: true,
          title: Text(name),
          subtitle: Text(text, textDirection: TextDirection.ltr),
        );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Where these come from'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        para(context.tr(
            "The units come from the Gemara, in fixed ratios: an amah is six tefachim, a revi'is a quarter of a log, and so on. "
            'What the poskim differ on is how big the base unit is today. The converter takes each posek\'s size for an amah, '
            'a beitzah or a perutah and works out every other unit from it. The common shiurim are listed as each posek ruled '
            "them, which isn't always what the ratios give: Rav Chaim Na'eh's kezayis is 27 ml, not half of his 57.6 ml beitzah.")),
        para(context.tr(
            "By default the app follows Rav Chaim Na'eh, whose figures are the most widely cited, and lists every other opinion "
            "beside his. You can follow Rav Moshe Feinstein or the Chazon Ish instead. For the time to walk a mil the default is "
            '18 minutes, the most widely used figure, and for eating a pras 4 minutes.')),
        for (final m in measures) ...[
          heading(_name(context, m.en, m.he)),
          para(m.basis),
          for (final o in m.opinions ?? const <Opinion>[]) source(_name(context, o.en, o.he), o.source),
          for (final u in m.units)
            for (final o in u.opinions ?? const <Opinion>[]) source('${_name(context, u.en, u.he)}: ${_name(context, o.en, o.he)}', o.source),
        ],
        heading(context.tr('Common shiurim')),
        for (final c in commonShiurim)
          for (final r in c.rulings)
            if (c.id != 'mil' && c.id != 'pras') source('${_name(context, c.en, c.he)}: ${_name(context, r.en, r.he)}', r.source),
        heading(context.tr('Credits')),
        para(credits),
      ]),
    );
  }
}
