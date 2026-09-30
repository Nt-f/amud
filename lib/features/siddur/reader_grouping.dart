import 'package:siddur_engine/siddur_engine.dart';

import '../../core/settings.dart';

/// How the reader groups and presents certain passages: the chazzan's
/// repetition, Kiddush / Kadesh, and rubrics made redundant by labels.

final _chazarahTitle = RegExp(
    r'^(?:kedusha|kedushah|kedushah for .*|birkat kohanim|birkas kohanim|priestly blessing|chazarat ha.?shatz|hazarat ha.?shatz|repetition.*)$',
    caseSensitive: false);
final _amidah = RegExp(r'amid|musaf|mussaf|shemoneh', caseSensitive: false);
final _personal = RegExp(r'kedushat hashem|holiness of god', caseSensitive: false);

/// Sections said only in the chazzan's repetition of the Amidah
/// (Kedushah, Birkas Kohanim).
bool isChazarahNode(SchemaNode n) {
  if (_personal.hasMatch(n.en)) return false;
  for (SchemaNode? x = n; x != null && !x.isRoot; x = x.parent) {
    if (_chazarahTitle.hasMatch(x.en.trim()) && x.ancestors.any((a) => _amidah.hasMatch(a.en))) return true;
  }
  return false;
}

/// Modim DeRabbanan: said by the congregation during the repetition.
bool isChazarahSegment(SegmentItem it) {
  if (it.kind != SegmentKind.prayer) return false;
  final he = it.he == null ? '' : normalizeRubric(it.he!.segment.html);
  final en = it.tr == null ? '' : stripHtml(it.tr!.segment.html).toLowerCase();
  return he.contains('אלהי כל בשר') || en.contains('god of all flesh');
}

final _unitTitle = RegExp(r'^kadesh$|kiddush', caseSensitive: false);
final _notUnit = RegExp(r'levan|zemirot', caseSensitive: false);

/// Kiddush / Kadesh leaves, shown as one card.
bool isUnitNode(SchemaNode n) => n.isLeaf && _unitTitle.hasMatch(n.en.trim()) && !_notUnit.hasMatch(n.en);

/// A short rubric line ("בקיץ:", "In winter:") whose meaning is already
/// shown as a label on the line that follows it.
bool isRedundantRubric(SegmentItem it, SegmentItem? next, AppSettings s) {
  if (it.kind != SegmentKind.instruction || next == null || next.kind != SegmentKind.prayer) return false;
  if (next.labelEn == null && next.labelHe == null) return false;
  final labelled = (next.applicability == Applicability.today && s.highlightToday) || (next.excluded && next.labelEn != null);
  if (!labelled) return false;
  bool short(ResolvedSegment? r) {
    if (r == null) return true;
    final t = stripHtml(r.segment.html).trim();
    return t.length <= 30 && t.endsWith(':');
  }

  return short(it.he) && short(it.tr);
}
