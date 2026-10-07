/// Data model for Sefaria-format siddurim bundled by tool/sefaria_sync.dart.
library;

/// A node of a book's table of contents.
class SchemaNode {
  final String en;
  final String he;
  final List<SchemaNode> children;
  final SchemaNode? parent;

  /// Titles from the root (exclusive) to this node (inclusive).
  final List<String> path;

  SchemaNode._(this.en, this.he, this.parent, this.path, this.children);

  bool get isLeaf => children.isEmpty;
  bool get isRoot => parent == null;

  /// `Weekday/Shacharit/Amidah` style id, stable across versions.
  String get id => path.join('/');

  Iterable<SchemaNode> get descendants sync* {
    for (final c in children) {
      yield c;
      yield* c.descendants;
    }
  }

  Iterable<SchemaNode> get leaves => isLeaf ? [this] : descendants.where((n) => n.isLeaf);

  List<SchemaNode> get ancestors {
    final out = <SchemaNode>[];
    var p = parent;
    while (p != null && !p.isRoot) {
      out.insert(0, p);
      p = p.parent;
    }
    return out;
  }

  SchemaNode? find(String id) {
    if (this.id == id) return this;
    for (final c in children) {
      if (id == c.id || id.startsWith('${c.id}/')) return c.find(id);
    }
    return null;
  }

  static SchemaNode parse(Map<String, dynamic> json, [SchemaNode? parent]) {
    final en = (json['enTitle'] ?? json['key'] ?? json['title'] ?? '') as String;
    final he = (json['heTitle'] ?? en) as String;
    final path = parent == null ? <String>[] : [...parent.path, en];
    final kids = <SchemaNode>[];
    final node = SchemaNode._(en, he, parent, path, kids);
    for (final c in (json['nodes'] as List? ?? const [])) {
      kids.add(parse(c as Map<String, dynamic>, node));
    }
    return node;
  }

  @override
  String toString() => 'SchemaNode($id)';
}

/// Metadata about one downloaded text version (from manifest.json).
class VersionInfo {
  final String language;
  final String actualLanguage;
  final String versionTitle;
  final String? versionTitleInHebrew;
  final String license;
  final String? source;
  final bool isPrimary;
  final String direction;
  final int segments;
  final String file;

  const VersionInfo({
    required this.language,
    required this.actualLanguage,
    required this.versionTitle,
    this.versionTitleInHebrew,
    required this.license,
    this.source,
    required this.isPrimary,
    required this.direction,
    required this.segments,
    required this.file,
  });

  bool get rtl => direction == 'rtl';

  /// Amud's own text (see corpus.dart), not a Sefaria version.
  bool get isCorpus => file.startsWith('corpus:');

  /// A redistributable license (public domain / Creative Commons).
  bool get openLicense => const {
        'public domain',
        'cc0',
        'cc-by',
        'cc-by-sa',
        'cc-by-nc',
        'cc-by-nc-sa',
      }.contains(license.toLowerCase());

  /// The version title with a trailing `[xx]` language tag, if present.
  String? get languageTag => RegExp(r'\[([a-z]{2,3})\]\s*$').firstMatch(versionTitle)?.group(1);

  factory VersionInfo.fromJson(Map<String, dynamic> j) => VersionInfo(
        language: j['language'] as String,
        actualLanguage: (j['actualLanguage'] ?? j['language']) as String,
        versionTitle: j['versionTitle'] as String,
        versionTitleInHebrew: j['versionTitleInHebrew'] as String?,
        license: (j['license'] as String?) ?? 'unknown',
        source: j['versionSource'] as String?,
        isPrimary: j['isPrimary'] == true,
        direction: (j['direction'] as String?) ?? 'ltr',
        segments: (j['segments'] as num?)?.toInt() ?? 0,
        file: j['file'] as String,
      );
}

/// A book listed in the manifest.
class BookInfo {
  final String title;
  final String heTitle;
  final String slug;
  final String indexFile;
  final List<VersionInfo> versions;
  const BookInfo(this.title, this.heTitle, this.slug, this.indexFile, this.versions);

  Iterable<VersionInfo> byLanguage(String lang) => versions.where((v) => v.language == lang);

  factory BookInfo.fromJson(Map<String, dynamic> j) => BookInfo(
        j['title'] as String,
        (j['heTitle'] ?? j['title']) as String,
        j['slug'] as String,
        j['index'] as String,
        [for (final v in j['versions'] as List) VersionInfo.fromJson(v as Map<String, dynamic>)],
      );
}

class Manifest {
  final List<BookInfo> books;
  final String source;
  const Manifest(this.books, this.source);

  BookInfo? book(String title) {
    for (final b in books) {
      if (b.title == title || b.slug == title) return b;
    }
    return null;
  }

  factory Manifest.fromJson(Map<String, dynamic> j) => Manifest(
        [for (final b in j['books'] as List) BookInfo.fromJson(b as Map<String, dynamic>)],
        (j['source'] as String?) ?? 'Sefaria',
      );
}

/// A loaded text version: nested maps (by English node title) whose leaves
/// are (possibly nested) lists of HTML strings.
class TextVersion {
  final VersionInfo info;
  final Object? text;
  TextVersion(this.info, this.text);

  /// Returns flattened segments for a leaf node path with their sub-refs,
  /// e.g. `[("1", html), ("2", html)]` or for depth-2 `("2:3", html)`.
  List<(String, String)>? segmentsAt(List<String> path) {
    Object? t = text;
    for (final p in path) {
      if (t is Map) {
        t = t[p] ?? t[''];
      } else {
        return null;
      }
    }
    // Default (unnamed) child nodes are stored under ''.
    while (t is Map && t.containsKey('')) {
      t = t[''];
    }
    if (t is! List) return null;
    final out = <(String, String)>[];
    void walk(Object? node, String prefix) {
      if (node is List) {
        for (var i = 0; i < node.length; i++) {
          walk(node[i], prefix.isEmpty ? '${i + 1}' : '$prefix:${i + 1}');
        }
      } else if (node is String && node.trim().isNotEmpty) {
        out.add((prefix, node));
      }
    }

    walk(t, '');
    return out.isEmpty ? null : out;
  }
}
