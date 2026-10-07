import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../core/titles.dart';
import 'prayer_catalog.dart';

/// Key points of a service to jump to, matched on section titles (first
/// match wins, so "Musaf Amidah" is Musaf, not Shemoneh Esrei).
const keyPoints = [
  ('Pesukei DeZimra', 'פסוקי דזמרה', r'pesukei d.{0,2}zimr'),
  ('Shema', 'שמע', r'shema'),
  ('Musaf', 'מוסף', r'mus+af'),
  ('Shemoneh Esrei', 'שמונה עשרה', r'^(?!post)(?:the )?amid|shemoneh esre|^magen avot|^magein avos'),
  ('Hallel', 'הלל', r'^hallel'),
  ('Tachanun', 'תחנון', r'ta(?:c)?h(?:a)?n(?:u)?n'),
  ('Torah reading', 'קריאת התורה', r'torah reading|reading of the torah|kriat ha.?torah|removing the torah'),
  ('Aleinu', 'עלינו', r'^al[ei]nu'),
  ('Candle lighting', 'הדלקת נרות', r'candle'),
  ('Kabbalat Shabbat', 'קבלת שבת', r'kabbal'),
  ('Kiddush Levana', 'קידוש לבנה', r'kiddush levan|blessing of the (?:new )?moon|birkat ha.?levana'),
  ('Kiddush', 'קידוש', r'kiddush'),
  ('Havdalah', 'הבדלה', r'havdal'),
  ('Sefirat HaOmer', 'ספירת העומר', r'sefir[ao][ts]? ha.?omer|counting (?:of )?the omer|^omer'),
];

/// The key point a section title is, if any.
(String, String)? keyPointFor(String title) {
  for (final (en, he, re) in keyPoints) {
    if (RegExp(re, caseSensitive: false).hasMatch(title)) return (en, he);
  }
  return null;
}

/// A place in the reader's list ([row]), or a part of today's davening
/// printed elsewhere ([elsewhere], which opens it).
class JumpPoint {
  final String en;
  final String he;
  final int? row;
  final PrayerRef? elsewhere;
  const JumpPoint(this.en, this.he, {this.row, this.elsewhere});
}

/// Chips under the reader's title that jump to the service's key points.
/// The chip of the part on screen stays marked and in view.
class ReaderJumpBar extends ConsumerStatefulWidget {
  final List<JumpPoint> points;
  final int active;
  final ValueChanged<JumpPoint> onTap;
  const ReaderJumpBar({super.key, required this.points, required this.active, required this.onTap});

  @override
  ConsumerState<ReaderJumpBar> createState() => _ReaderJumpBarState();
}

class _ReaderJumpBarState extends ConsumerState<ReaderJumpBar> {
  List<GlobalKey> _keys = [];

  @override
  void didUpdateWidget(ReaderJumpBar old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = widget.active < _keys.length ? _keys[widget.active].currentContext : null;
        if (c != null) Scrollable.ensureVisible(c, alignment: 0.5, duration: const Duration(milliseconds: 200));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    if (_keys.length != widget.points.length) _keys = [for (final _ in widget.points) GlobalKey()];
    final hebrew = context.prayerTitleIsHebrew(s);
    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: 48,
        // Every chip is built (not lazily), so any can be scrolled into view.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            for (final (i, p) in widget.points.indexed)
              Padding(
                key: _keys[i],
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  avatar: p.elsewhere == null ? null : Icon(Icons.north_east, size: 14, color: theme.colorScheme.primary),
                  label: Text(context.prayerTitle(s, p.en, p.he), style: TextStyle(fontFamily: hebrew ? s.hebrewFont : null)),
                  selected: p.row != null && i == widget.active,
                  onSelected: (_) => widget.onTap(p),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
