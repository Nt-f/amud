import 'package:siddur_engine/siddur_engine.dart';

import '../../core/settings.dart';

/// How the reader groups and presents certain passages: the chazzan's
/// repetition, Kiddush / Kadesh, and rubrics made redundant by labels.

final _chazarahTitle = RegExp(
    r'^(?:kedusha|kedushah|keduasha|kedushah for .*|birkat kohanim|birkas kohanim|priestly blessing|chazarat ha.?shatz|hazarat ha.?shatz|repetition.*)$',
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

const _kaddishTitles = {
  'kaddish.half': ('Half Kaddish', 'חצי קדיש'),
  'kaddish.shalem': ('Kaddish Shalem', 'קדיש שלם'),
  'kaddish.mourners': ("Mourner's Kaddish", 'קדיש יתום'),
  'kaddish.derabbanan': ("Kaddish DeRabbanan", 'קדיש דרבנן'),
  'kaddish.burial': ('Kaddish after a burial', 'קדיש אחר הקבורה'),
  'kaddish.siyum': ('Kaddish after a siyum', 'קדיש אחר סיום'),
};

/// The title (English, Hebrew) of the Kaddish a line belongs to, from its
/// graph node (`kaddish.half`), or null when it isn't part of one. Wherever
/// a Kaddish is printed, in its own section or inside another, it is one card.
(String, String)? kaddishUnit(String? graphNode) {
  if (graphNode == null || !graphNode.startsWith('kaddish.')) return null;
  return _kaddishTitles[graphNode] ?? ('Kaddish', 'קדיש');
}

/// A rubric line ("בקיץ:", "On Rosh Chodesh and Chol HaMoed say:") whose
/// meaning is already shown as a label on the line that follows it.
bool isRedundantRubric(SegmentItem it, SegmentItem? next, AppSettings s) {
  if (it.kind != SegmentKind.instruction || next == null || next.kind != SegmentKind.prayer) return false;
  if (next.labelEn == null && next.labelHe == null) return false;
  final labelled = (next.applicability == Applicability.today && s.highlightToday) || (next.excluded && next.labelEn != null);
  if (!labelled) return false;
  if (it.announces) return true;
  bool short(ResolvedSegment? r) {
    if (r == null) return true;
    final t = stripHtml(r.segment.html).trim();
    return t.length <= 30 && t.endsWith(':');
  }

  return short(it.he) && short(it.tr);
}
