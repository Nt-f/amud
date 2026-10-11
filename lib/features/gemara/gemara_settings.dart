import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/content.dart';
import '../../core/providers.dart';

/// The ways to read an amud.
enum GemaraView {
  /// The printed page: Gemara in the middle, Rashi and Tosafot around it.
  daf,

  /// Each segment's Hebrew, then its English with the explanation woven in
  /// (bold is the literal translation).
  elucidated,

  /// Hebrew and English in two columns, segment beside segment.
  sideBySide,

  /// Each Hebrew phrase followed by its English, as in an elucidated
  /// translation; needs the word-by-word layer.
  phrase,

  /// Every word with its English under it, line by line; needs the
  /// word-by-word layer.
  interlinear,
}

/// What the tooltip on the printed page shows for a tapped word.
enum DafTip {
  /// The passage's English.
  translation,

  /// The passage phrase by phrase (needs the word-by-word layer).
  phrases,

  /// The tapped word and its English (needs the word-by-word layer).
  words,
}

class GemaraSettings {
  /// The Bavli's view; [otherViews] keeps each other text's own ("mishnah",
  /// "kitzur" → view name).
  final GemaraView view;
  final Map<String, String> otherViews;

  /// Show the translator's explanation (the plain text between the bold
  /// literal translation). Off: only the literal translation.
  final bool elucidation;

  /// Show Rashi and Tosafot under each segment in the reading views.
  final bool inlineCommentary;

  /// Where the word-by-word layer comes from. Empty: none.
  final String interlinearServer;

  /// Width of the printed page, as a fraction of the screen (the page can
  /// also be pinched).
  final double dafScale;

  final DafTip dafTip;

  /// With word-by-word taps on the page, also mark the rest of the tapped
  /// word's phrase (lightly).
  final bool dafPhrase;

  const GemaraSettings({
    this.view = GemaraView.elucidated,
    this.otherViews = const {},
    this.elucidation = true,
    this.inlineCommentary = false,
    this.interlinearServer = contentServer,
    this.dafScale = 1,
    this.dafTip = DafTip.translation,
    this.dafPhrase = false,
  });

  GemaraSettings copyWith({
    GemaraView? view,
    Map<String, String>? otherViews,
    bool? elucidation,
    bool? inlineCommentary,
    String? interlinearServer,
    double? dafScale,
    DafTip? dafTip,
    bool? dafPhrase,
  }) =>
      GemaraSettings(
        view: view ?? this.view,
        otherViews: otherViews ?? this.otherViews,
        elucidation: elucidation ?? this.elucidation,
        inlineCommentary: inlineCommentary ?? this.inlineCommentary,
        interlinearServer: interlinearServer ?? this.interlinearServer,
        dafScale: dafScale ?? this.dafScale,
        dafTip: dafTip ?? this.dafTip,
        dafPhrase: dafPhrase ?? this.dafPhrase,
      );

  Map<String, Object?> toJson() => {
        'view': view.name,
        'otherViews': otherViews,
        'elucidation': elucidation,
        'inlineCommentary': inlineCommentary,
        'interlinearServer': interlinearServer,
        'dafScale': dafScale,
        'dafTip': dafTip.name,
        'dafPhrase': dafPhrase,
      };

  factory GemaraSettings.fromJson(Map<String, Object?> j) {
    const d = GemaraSettings();
    return GemaraSettings(
      view: GemaraView.values.asNameMap()[j['view']] ?? d.view,
      otherViews: {for (final e in ((j['otherViews'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      elucidation: j['elucidation'] is bool ? j['elucidation'] as bool : d.elucidation,
      inlineCommentary: j['inlineCommentary'] is bool ? j['inlineCommentary'] as bool : d.inlineCommentary,
      // talmud.dev was the default before the content site; it never served these.
      interlinearServer: j['interlinearServer'] is String && j['interlinearServer'] != 'https://talmud.dev' ? j['interlinearServer'] as String : d.interlinearServer,
      dafScale: j['dafScale'] is num ? (j['dafScale'] as num).toDouble() : d.dafScale,
      dafTip: DafTip.values.asNameMap()[j['dafTip']] ?? d.dafTip,
      dafPhrase: j['dafPhrase'] is bool ? j['dafPhrase'] as bool : d.dafPhrase,
    );
  }
}

extension GemaraSettingsViews on GemaraSettings {
  /// The view for a kind of text ('bavli', 'mishnah', 'kitzur'), among the
  /// views it supports.
  GemaraView viewFor(String kind, List<GemaraView> supported) {
    final v = kind == 'bavli' ? view : (GemaraView.values.asNameMap()[otherViews[kind]] ?? GemaraView.elucidated);
    return supported.contains(v) ? v : GemaraView.elucidated;
  }

  GemaraSettings withView(String kind, GemaraView v) =>
      kind == 'bavli' ? copyWith(view: v) : copyWith(otherViews: {...otherViews, kind: v.name});
}

class GemaraSettingsNotifier extends Notifier<GemaraSettings> {
  static const _key = 'gemaraSettings';

  @override
  GemaraSettings build() =>
      ref.watch(storageProvider).readJson(_key, (j) => GemaraSettings.fromJson((j as Map).cast<String, Object?>())) ?? const GemaraSettings();

  void update(GemaraSettings Function(GemaraSettings) f) {
    final old = state.toJson();
    state = f(state);
    final now = state.toJson();
    ref.read(storageProvider).writeJson(_key, now);
    for (final k in now.keys) {
      if (old[k] != now[k] && k != 'interlinearServer') analytics.settingChanged('gemara_$k', now[k]);
    }
  }
}

final gemaraSettingsProvider = NotifierProvider<GemaraSettingsNotifier, GemaraSettings>(GemaraSettingsNotifier.new);
