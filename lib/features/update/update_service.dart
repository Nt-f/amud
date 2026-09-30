import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/providers.dart';
import '../alerts/alerts.dart';

/// Where releases are published (GitHub Releases, built by
/// .github/workflows/build.yml on a `v*` tag).
const updateRepo = 'Nt-f/flutter_siddur';

/// A published release newer than the running app.
class UpdateInfo {
  final String version;
  final String notes;
  final String pageUrl;

  /// This platform's download (APK / Windows zip), if the release has one.
  final String? downloadUrl;
  final int? downloadSize;
  const UpdateInfo({required this.version, required this.notes, required this.pageUrl, this.downloadUrl, this.downloadSize});
}

/// Whether this platform installs from a downloaded release file. The web
/// app updates itself through its service worker instead.
bool get updatesSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// The release file for this platform, by name.
bool _assetFor(String name) {
  final n = name.toLowerCase();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => n.endsWith('.apk'),
    TargetPlatform.windows => n.contains('windows') && (n.endsWith('.zip') || n.endsWith('.exe') || n.endsWith('.msix')),
    TargetPlatform.linux => n.contains('linux') && (n.endsWith('.tar.gz') || n.endsWith('.zip') || n.endsWith('.appimage')),
    _ => false,
  };
}

/// Compares dotted versions ("1.2.10" > "1.2.9"); a leading "v" and any
/// "+build" suffix are ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final p in v.replaceFirst(RegExp('^v'), '').split('+').first.split(RegExp(r'[.-]')))
          int.tryParse(p) ?? 0,
      ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

class UpdateState {
  final String currentVersion;
  final UpdateInfo? available;
  final bool checking;
  final String? error;
  final DateTime? lastCheck;

  /// Check once a day in the background and notify.
  final bool autoCheck;

  /// A version the user chose to skip (no banner or notification for it).
  final String? skipped;

  /// The last version a notification was shown for.
  final String? notified;

  const UpdateState({
    this.currentVersion = '',
    this.available,
    this.checking = false,
    this.error,
    this.lastCheck,
    this.autoCheck = true,
    this.skipped,
    this.notified,
  });

  /// An update the user hasn't dismissed.
  UpdateInfo? get pending => available != null && available!.version != skipped ? available : null;

  UpdateState copyWith({
    String? currentVersion,
    UpdateInfo? Function()? available,
    bool? checking,
    String? Function()? error,
    DateTime? lastCheck,
    bool? autoCheck,
    String? Function()? skipped,
    String? notified,
  }) =>
      UpdateState(
        currentVersion: currentVersion ?? this.currentVersion,
        available: available != null ? available() : this.available,
        checking: checking ?? this.checking,
        error: error != null ? error() : this.error,
        lastCheck: lastCheck ?? this.lastCheck,
        autoCheck: autoCheck ?? this.autoCheck,
        skipped: skipped != null ? skipped() : this.skipped,
        notified: notified ?? this.notified,
      );
}

class UpdateNotifier extends Notifier<UpdateState> {
  static const _key = 'update';

  @override
  UpdateState build() {
    final j = ref.read(storageProvider).readJson(_key, (j) => (j as Map).cast<String, Object?>()) ?? const {};
    return UpdateState(
      lastCheck: DateTime.tryParse('${j['lastCheck']}'),
      autoCheck: j['autoCheck'] != false,
      skipped: j['skipped'] as String?,
      notified: j['notified'] as String?,
    );
  }

  void _save() => ref.read(storageProvider).writeJson(_key, {
        'lastCheck': state.lastCheck?.toIso8601String(),
        'autoCheck': state.autoCheck,
        'skipped': state.skipped,
        'notified': state.notified,
      });

  void setAutoCheck(bool v) {
    state = state.copyWith(autoCheck: v);
    _save();
  }

  void skip(String version) {
    state = state.copyWith(skipped: () => version);
    _save();
  }

  /// Background check at startup: at most once a day, and a notification
  /// the first time a new version is seen.
  Future<void> autoCheck() async {
    if (!updatesSupported || !state.autoCheck) return;
    final last = state.lastCheck;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) {
      // Still learn our own version for the About screen.
      await _loadVersion();
      return;
    }
    await check();
    final u = state.pending;
    if (u != null && state.notified != u.version) {
      state = state.copyWith(notified: u.version);
      _save();
      try {
        await ref.read(notificationBackendProvider).showNow(
              'Siddur ${u.version} is available',
              'Tap to see what\'s new and download the update.',
              route: '/update',
              id: 998,
            );
      } catch (e) {
        debugPrint('update notification failed: $e');
      }
    }
  }

  Future<void> _loadVersion() async {
    if (state.currentVersion.isNotEmpty) return;
    try {
      final info = await PackageInfo.fromPlatform();
      state = state.copyWith(currentVersion: info.version);
    } catch (_) {}
  }

  /// Asks GitHub for the latest release. Returns the update, if newer.
  Future<UpdateInfo?> check() async {
    await _loadVersion();
    state = state.copyWith(checking: true, error: () => null);
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) {
        // No release published yet.
        state = state.copyWith(checking: false, available: () => null, lastCheck: DateTime.now());
        _save();
        return null;
      }
      if (res.statusCode != 200) throw 'GitHub returned ${res.statusCode}';
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final version = ((j['tag_name'] as String?) ?? '').replaceFirst(RegExp('^v'), '');
      Map<String, dynamic>? asset;
      for (final a in (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        if (_assetFor(a['name'] as String? ?? '')) {
          asset = a;
          break;
        }
      }
      final newer = version.isNotEmpty && compareVersions(version, state.currentVersion) > 0;
      final info = newer
          ? UpdateInfo(
              version: version,
              notes: (j['body'] as String?)?.trim() ?? '',
              pageUrl: (j['html_url'] as String?) ?? 'https://github.com/$updateRepo/releases/latest',
              downloadUrl: asset?['browser_download_url'] as String?,
              downloadSize: (asset?['size'] as num?)?.toInt(),
            )
          : null;
      state = state.copyWith(checking: false, available: () => info, lastCheck: DateTime.now());
      _save();
      return info;
    } catch (e) {
      state = state.copyWith(checking: false, error: () => '$e');
      return null;
    }
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
