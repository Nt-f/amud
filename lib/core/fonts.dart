import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'providers.dart';
import 'settings.dart';
import 'storage.dart';

enum FontCategory {
  cantillation('Siddur & te\'amim'),
  serif('Serif'),
  sans('Sans serif'),
  handwriting('Handwriting'),
  stam('STaM (scribal)'),
  display('Display'),
  mono('Monospace'),
  user('Uploaded');

  final String label;
  const FontCategory(this.label);
}

/// A font family available to the reader.
class FontEntry {
  final String family;
  final String label;
  final bool builtIn;
  final FontCategory category;
  final String license;
  final String? designer;

  /// Where to fetch the font from when it isn't bundled (Google Fonts'
  /// GitHub repository, which allows cross-origin requests on web).
  final String? url;
  final String? note;

  /// Whether the font has cantillation marks (te'amim) and vowel points.
  final bool teamim;
  final bool nikud;
  const FontEntry(
    this.family,
    this.label, {
    this.builtIn = false,
    this.category = FontCategory.user,
    this.license = '',
    this.designer,
    this.url,
    this.note,
    this.teamim = true,
    this.nikud = true,
  });

  bool get remote => url != null;

  Map<String, Object?> toJson() => {'family': family, 'label': label};
}

const _clm = 'GPL-2.0 + font exception';

/// Fonts shipped in the app bundle (see pubspec.yaml), usable offline.
const builtInFonts = [
  FontEntry('FrankRuhlLibre', 'Frank Ruhl Libre', builtIn: true, category: FontCategory.serif, license: 'OFL', designer: 'Yanek Iontef', teamim: false),
  FontEntry('NotoSerifHebrew', 'Noto Serif Hebrew', builtIn: true, category: FontCategory.serif, license: 'OFL', designer: 'Google'),
  FontEntry('DavidLibre', 'David Libre', builtIn: true, category: FontCategory.serif, license: 'OFL', designer: 'Monotype / Meir Sadan', teamim: false),
  FontEntry('TaameyFrankCLM', 'Taamey Frank CLM', builtIn: true, category: FontCategory.cantillation, license: _clm,
      designer: 'Yoram Gnat (Culmus)', note: 'Frank-Rühl style with full cantillation support'),
  FontEntry('TaameyDavidCLM', 'Taamey David CLM', builtIn: true, category: FontCategory.cantillation, license: _clm,
      designer: 'Yoram Gnat (Culmus)', note: 'David style with full cantillation support'),
  FontEntry('TaameyAshkenaz', 'Taamey Ashkenaz', builtIn: true, category: FontCategory.cantillation, license: _clm,
      designer: 'Yoram Gnat (Culmus)', note: 'Classic Ashkenazi siddur typeface'),
  FontEntry('KeterYG', 'Keter YG', builtIn: true, category: FontCategory.cantillation, license: _clm,
      designer: 'Yoram Gnat (Culmus)', note: 'Modelled on the Aleppo Codex'),
  FontEntry('KeterAramTsova', 'Keter Aram Tsova', builtIn: true, category: FontCategory.cantillation, license: _clm,
      designer: 'Yoram Gnat (Culmus)', note: 'Aleppo Codex style'),
  FontEntry('EzraSIL', 'Ezra SIL', builtIn: true, category: FontCategory.cantillation, license: 'OFL', designer: 'SIL International',
      note: 'Biblical Hebrew with cantillation'),
  FontEntry('EzraSILSR', 'Ezra SIL SR', builtIn: true, category: FontCategory.cantillation, license: 'OFL', designer: 'SIL International',
      note: 'Ezra with alternate mark placement'),
  FontEntry('FrankRuehlCLM', 'Frank Ruehl CLM', builtIn: true, category: FontCategory.serif, license: _clm, designer: 'Culmus'),
  FontEntry('DavidCLM', 'David CLM', builtIn: true, category: FontCategory.serif, license: _clm, designer: 'Culmus', teamim: false),
  FontEntry('DrugulinCLM', 'Drugulin CLM', builtIn: true, category: FontCategory.serif, license: _clm, designer: 'Culmus'),
  FontEntry('HadasimCLM', 'Hadasim CLM', builtIn: true, category: FontCategory.serif, license: _clm, designer: 'Culmus'),
  FontEntry('ElliniaCLM', 'Ellinia CLM', builtIn: true, category: FontCategory.serif, license: _clm, designer: 'Culmus', teamim: false, nikud: false),
  FontEntry('Shofar', 'Shofar', builtIn: true, category: FontCategory.serif, license: _clm, designer: 'Yoram Gnat (Culmus)'),
  FontEntry('MiriamCLM', 'Miriam CLM', builtIn: true, category: FontCategory.sans, license: _clm, designer: 'Culmus', teamim: false),
  FontEntry('NachlieliCLM', 'Nachlieli CLM', builtIn: true, category: FontCategory.sans, license: _clm, designer: 'Culmus'),
  FontEntry('YehudaCLM', 'Yehuda CLM', builtIn: true, category: FontCategory.sans, license: _clm, designer: 'Culmus', teamim: false, nikud: false),
  FontEntry('AharoniCLM', 'Aharoni CLM', builtIn: true, category: FontCategory.sans, license: _clm, designer: 'Culmus', teamim: false),
  FontEntry('SimpleCLM', 'Simple CLM', builtIn: true, category: FontCategory.sans, license: _clm, designer: 'Yoram Gnat (Culmus)'),
  FontEntry('StamAshkenazCLM', 'Stam Ashkenaz CLM', builtIn: true, category: FontCategory.stam, license: _clm, designer: 'Culmus',
      note: 'Torah-scroll lettering'),
  FontEntry('StamSefaradCLM', 'Stam Sefarad CLM', builtIn: true, category: FontCategory.stam, license: _clm, designer: 'Culmus',
      note: 'Torah-scroll lettering'),
  FontEntry('MiriamMonoCLM', 'Miriam Mono CLM', builtIn: true, category: FontCategory.mono, license: _clm, designer: 'Culmus'),
];

const _gf = 'https://raw.githubusercontent.com/google/fonts/main/';

FontEntry _g(String label, String path, FontCategory c, {String license = 'OFL', String? note, bool nikud = true}) =>
    FontEntry('gf_${label.replaceAll(RegExp('[^A-Za-z0-9]'), '')}', label,
        category: c, license: license, designer: 'Google Fonts', url: '$_gf$path', note: note, nikud: nikud, teamim: _gfTeamim.contains(label));

/// Google Fonts families that include the cantillation marks.
const _gfTeamim = {'Arimo', 'Cardo', 'Cousine', 'Google Sans', 'Lunasima', 'M PLUS 1p', 'M PLUS Rounded 1c', 'Noto Rashi Hebrew', 'Noto Sans Hebrew', 'Tinos'};

/// Every Google Fonts family with a Hebrew subset, downloaded on demand.
final googleHebrewFonts = [
  _g('Alef', 'ofl/alef/Alef-Regular.ttf', FontCategory.sans),
  _g('Arimo', 'ofl/arimo/Arimo[wght].ttf', FontCategory.sans),
  _g('Assistant', 'ofl/assistant/Assistant[wght].ttf', FontCategory.sans),
  _g('Fredoka', 'ofl/fredoka/Fredoka[wdth,wght].ttf', FontCategory.sans),
  _g('Google Sans', 'ofl/googlesans/GoogleSans[GRAD,opsz,wght].ttf', FontCategory.sans),
  _g('Heebo', 'ofl/heebo/Heebo[wght].ttf', FontCategory.sans),
  _g('IBM Plex Sans Hebrew', 'ofl/ibmplexsanshebrew/IBMPlexSansHebrew-Regular.ttf', FontCategory.sans),
  _g('Lunasima', 'ofl/lunasima/Lunasima-Regular.ttf', FontCategory.sans),
  _g('M PLUS 1p', 'ofl/mplus1p/MPLUS1p-Regular.ttf', FontCategory.sans, note: 'Large download (Japanese coverage)'),
  _g('M PLUS Rounded 1c', 'ofl/mplusrounded1c/MPLUSRounded1c-Regular.ttf', FontCategory.sans, note: 'Large download (Japanese coverage)'),
  _g('Miriam Libre', 'ofl/miriamlibre/MiriamLibre[wght].ttf', FontCategory.sans),
  _g('Noto Sans Hebrew', 'ofl/notosanshebrew/NotoSansHebrew[wdth,wght].ttf', FontCategory.sans),
  _g('Open Sans', 'ofl/opensans/OpenSans[wdth,wght].ttf', FontCategory.sans),
  _g('Rubik', 'ofl/rubik/Rubik[wght].ttf', FontCategory.sans),
  _g('Secular One', 'ofl/secularone/SecularOne-Regular.ttf', FontCategory.sans),
  _g('Varela Round', 'ofl/varelaround/VarelaRound-Regular.ttf', FontCategory.sans),
  _g('Bellefair', 'ofl/bellefair/Bellefair-Regular.ttf', FontCategory.serif),
  _g('Bona Nova', 'ofl/bonanova/BonaNova-Regular.ttf', FontCategory.serif),
  _g('Bona Nova SC', 'ofl/bonanovasc/BonaNovaSC-Regular.ttf', FontCategory.serif),
  _g('Cardo', 'ofl/cardo/Cardo-Regular.ttf', FontCategory.serif, note: 'Scholarly serif with Biblical Hebrew marks'),
  _g('Libertinus Serif', 'ofl/libertinusserif/LibertinusSerif-Regular.ttf', FontCategory.serif),
  _g('Noto Rashi Hebrew', 'ofl/notorashihebrew/NotoRashiHebrew[wght].ttf', FontCategory.serif, note: 'Rashi script'),
  _g('Suez One', 'ofl/suezone/SuezOne-Regular.ttf', FontCategory.serif),
  _g('Tinos', 'ofl/tinos/Tinos-Regular.ttf', FontCategory.serif),
  _g('Amatic SC', 'ofl/amaticsc/AmaticSC-Regular.ttf', FontCategory.handwriting),
  _g('Gveret Levin', 'ofl/gveretlevin/GveretLevin-Regular.ttf', FontCategory.handwriting),
  _g('Playpen Sans Hebrew', 'ofl/playpensanshebrew/PlaypenSansHebrew[wght].ttf', FontCategory.handwriting),
  _g('Solitreo', 'ofl/solitreo/Solitreo-Regular.ttf', FontCategory.handwriting, note: 'Sephardic cursive'),
  _g('Cousine', 'ofl/cousine/Cousine-Regular.ttf', FontCategory.mono),
  _g('Cascadia Code', 'ofl/cascadiacode/CascadiaCode[wght].ttf', FontCategory.mono, nikud: false),
  _g('Cascadia Mono', 'ofl/cascadiamono/CascadiaMono[wght].ttf', FontCategory.mono, nikud: false),
  _g('Handjet', 'ofl/handjet/Handjet[ELGR,ELSH,wght].ttf', FontCategory.display),
  _g('Karantina', 'ofl/karantina/Karantina-Regular.ttf', FontCategory.display),
  for (final (name, file) in const [
    ('80s Fade', 'Rubik80sFade'),
    ('Beastly', 'RubikBeastly'),
    ('Broken Fax', 'RubikBrokenFax'),
    ('Bubbles', 'RubikBubbles'),
    ('Burned', 'RubikBurned'),
    ('Dirt', 'RubikDirt'),
    ('Distressed', 'RubikDistressed'),
    ('Doodle Shadow', 'RubikDoodleShadow'),
    ('Doodle Triangles', 'RubikDoodleTriangles'),
    ('Gemstones', 'RubikGemstones'),
    ('Glitch', 'RubikGlitch'),
    ('Glitch Pop', 'RubikGlitchPop'),
    ('Iso', 'RubikIso'),
    ('Lines', 'RubikLines'),
    ('Maps', 'RubikMaps'),
    ('Marker Hatch', 'RubikMarkerHatch'),
    ('Maze', 'RubikMaze'),
    ('Microbe', 'RubikMicrobe'),
    ('Moonrocks', 'RubikMoonrocks'),
    ('Pixels', 'RubikPixels'),
    ('Puddles', 'RubikPuddles'),
    ('Scribble', 'RubikScribble'),
    ('Spray Paint', 'RubikSprayPaint'),
    ('Storm', 'RubikStorm'),
    ('Vinyl', 'RubikVinyl'),
    ('Wet Paint', 'RubikWetPaint'),
  ])
    _g('Rubik $name', 'ofl/${file.toLowerCase()}/$file-Regular.ttf', FontCategory.display),
];

/// All catalogued (bundled + downloadable) fonts.
final fontCatalog = [...builtInFonts, ...googleHebrewFonts];

FontEntry? catalogFont(String family) {
  for (final f in fontCatalog) {
    if (f.family == family) return f;
  }
  return null;
}

/// The font to use for Hebrew text in [family]: the font itself when it has
/// the marks the text needs, otherwise a similar bundled font that does
/// (so trop isn't drawn from a mismatched fallback font).
String hebrewFamilyFor(String family, {required bool teamim, required bool nikud}) {
  final f = catalogFont(family);
  if (f == null || (f.teamim || !teamim) && (f.nikud || !nikud)) return family;
  if (family.contains('David')) return 'TaameyDavidCLM';
  if (f.category == FontCategory.sans || f.category == FontCategory.mono) return 'SimpleCLM';
  return 'TaameyFrankCLM';
}

/// Display name for a font family, including uploaded fonts.
String fontLabel(String family, List<FontEntry> userFonts) {
  for (final f in [...fontCatalog, ...userFonts]) {
    if (f.family == family) return f.label;
  }
  return family;
}

/// User-uploaded TTF/OTF fonts. Bytes are persisted (IndexedDB on web,
/// app storage on devices) and registered at runtime with [FontLoader],
/// which works on every Flutter platform including web.
class FontRepository extends Notifier<List<FontEntry>> {
  static const _metaKey = 'userFonts';

  Storage get _storage => ref.read(storageProvider);

  @override
  List<FontEntry> build() {
    final meta = ref.watch(storageProvider).readJson(
            _metaKey,
            (j) => [
                  for (final e in (j as List).cast<Map>())
                    FontEntry(e['family'] as String, e['label'] as String),
                ]) ??
        const <FontEntry>[];
    return meta;
  }

  List<FontEntry> get all => [...builtInFonts, ...state];

  /// Registers all stored user fonts, and the chosen downloadable font, with
  /// the engine. Call once at startup.
  Future<void> loadAll() async {
    for (final f in state) {
      final bytes = _storage.readBlob('font:${f.family}');
      if (bytes != null) await _register(f.family, bytes);
    }
    // The siddur's font and the Torah tab's (stored separately).
    final torah = _storage.readJson('torahSettings', (j) => (j as Map)['hebrewFont'] as String?);
    for (final chosen in {ref.read(settingsProvider).hebrewFont, ?torah}) {
      if (chosen.startsWith('gf_')) await ref.read(remoteFontsProvider.notifier).loadCached(chosen);
    }
  }

  static Future<void> _register(String family, List<int> bytes) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  }

  /// Prompts for font files and imports them. Returns imported entries.
  Future<List<FontEntry>> pickAndImport() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['ttf', 'otf']);
    final added = <FontEntry>[];
    for (final f in files) {
      final bytes = await f.xFile.readAsBytes();
      final label = f.name.replaceAll(RegExp(r'\.(ttf|otf)$', caseSensitive: false), '');
      added.add(await importBytes(label, bytes));
    }
    return added;
  }

  Future<FontEntry> importBytes(String label, List<int> bytes) async {
    if (bytes.length < 12) throw const FormatException('Not a font file');
    final sig = bytes.sublist(0, 4);
    final ok = (sig[0] == 0 && sig[1] == 1 && sig[2] == 0 && sig[3] == 0) || // TrueType
        String.fromCharCodes(sig) == 'OTTO' || // OpenType CFF
        String.fromCharCodes(sig) == 'true';
    if (!ok) throw const FormatException('Only TrueType (.ttf) or OpenType (.otf) fonts are supported');
    final family = 'user_${DateTime.now().microsecondsSinceEpoch}';
    await _storage.writeBlob('font:$family', bytes);
    await _register(family, bytes);
    final entry = FontEntry(family, label);
    state = [...state, entry];
    await _storage.writeJson(_metaKey, [for (final e in state) e.toJson()]);
    return entry;
  }

  Future<void> remove(String family) async {
    await _storage.deleteBlob('font:$family');
    state = state.where((f) => f.family != family).toList();
    await _storage.writeJson(_metaKey, [for (final e in state) e.toJson()]);
  }
}

final fontsProvider = NotifierProvider<FontRepository, List<FontEntry>>(FontRepository.new);

enum FontLoadState { loading, ready, error }

/// Downloads catalogued fonts for previewing. Previews stay in memory;
/// only a font the user selects is saved for offline use.
class RemoteFonts extends Notifier<Map<String, FontLoadState>> {
  final _bytes = <String, List<int>>{};

  Storage get _storage => ref.read(storageProvider);

  @override
  Map<String, FontLoadState> build() => const {};

  void _set(String family, FontLoadState s) => state = {...state, family: s};

  bool isSaved(String family) => _storage.readBlob('font:$family') != null;

  Future<void> loadCached(String family) async {
    final bytes = _storage.readBlob('font:$family');
    if (bytes == null) return;
    await FontRepository._register(family, bytes);
    _set(family, FontLoadState.ready);
  }

  /// Makes [f] renderable, downloading it if needed.
  Future<void> ensure(FontEntry f) async {
    if (!f.remote) return;
    final s = state[f.family];
    if (s == FontLoadState.ready || s == FontLoadState.loading) return;
    _set(f.family, FontLoadState.loading);
    try {
      var bytes = _storage.readBlob('font:${f.family}');
      if (bytes == null) {
        final res = await http.get(Uri.parse(f.url!));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        bytes = res.bodyBytes;
        _bytes[f.family] = bytes;
      }
      await FontRepository._register(f.family, bytes);
      _set(f.family, FontLoadState.ready);
    } catch (_) {
      _set(f.family, FontLoadState.error);
    }
  }

  /// Downloads (if needed) and saves [f] so it works offline.
  Future<void> save(FontEntry f) async {
    await ensure(f);
    final bytes = _bytes.remove(f.family);
    if (bytes != null) await _storage.writeBlob('font:${f.family}', bytes);
  }
}

final remoteFontsProvider = NotifierProvider<RemoteFonts, Map<String, FontLoadState>>(RemoteFonts.new);
