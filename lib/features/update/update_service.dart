import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/providers.dart';
import '../alerts/alerts.dart';
import 'apk_installer.dart';
import '../../core/analytics.dart';

/// Where releases are published (GitHub Releases, built by
/// .github/workflows/build.yml on a `v*` tag).
const updateRepo = 'Nt-f/amud';

/// A published release newer than the running app.
class UpdateInfo {
  final String version;
  final String notes;
  final String pageUrl;

  /// This platform's download (APK / Windows zip), if the release has one.
  final String? downloadUrl;
  final int? downloadSize;

  /// The download's SHA-256 (hex), when GitHub lists one.
  final String? sha256;
  const UpdateInfo(
      {required this.version, required this.notes, required this.pageUrl, this.downloadUrl, this.downloadSize, this.sha256});
}

/// Whether updates download and install inside the app (Android). Elsewhere
/// the download opens in the browser.
bool get installsInApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Whether this platform installs from a downloaded release file. The web
/// app updates itself through its service worker instead.
bool get updatesSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// The release file for this platform, by name.
bool _assetFor(String name) {
  final n = name.toLowerCase();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => n.endsWith('.apk') && !n.contains('wear'),
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

  /// Download progress (0–1) while an update downloads; null otherwise.
  final double? downloading;

  /// Waiting for the user to allow installs from this app.
  final bool needsPermission;

  /// The last version whose release notes were offered after updating.
  final String? seenVersion;

  /// Release notes for the installed version, once known.
  final String? installedNotes;

  /// Notes saved when an update was found, shown after it's installed.
  final String? savedNotesVersion;
  final String? savedNotes;

  const UpdateState({
    this.currentVersion = '',
    this.available,
    this.checking = false,
    this.error,
    this.lastCheck,
    this.autoCheck = true,
    this.skipped,
    this.notified,
    this.downloading,
    this.needsPermission = false,
    this.seenVersion,
    this.installedNotes,
    this.savedNotesVersion,
    this.savedNotes,
  });

  /// An update the user hasn't dismissed.
  UpdateInfo? get pending => available != null && available!.version != skipped ? available : null;

  /// The app was updated and the user hasn't looked at what changed yet.
  bool get justUpdated =>
      currentVersion.isNotEmpty && seenVersion != null && compareVersions(currentVersion, seenVersion!) > 0;

  UpdateState copyWith({
    String? currentVersion,
    UpdateInfo? Function()? available,
    bool? checking,
    String? Function()? error,
    DateTime? lastCheck,
    bool? autoCheck,
    String? Function()? skipped,
    String? notified,
    double? Function()? downloading,
    bool? needsPermission,
    String? seenVersion,
    String? Function()? installedNotes,
    String? savedNotesVersion,
    String? savedNotes,
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
        downloading: downloading != null ? downloading() : this.downloading,
        needsPermission: needsPermission ?? this.needsPermission,
        seenVersion: seenVersion ?? this.seenVersion,
        installedNotes: installedNotes != null ? installedNotes() : this.installedNotes,
        savedNotesVersion: savedNotesVersion ?? this.savedNotesVersion,
        savedNotes: savedNotes ?? this.savedNotes,
      );
}

class UpdateNotifier extends Notifier<UpdateState> {
  static const _key = 'update';
  static const _offline = "GitHub couldn't be reached. Check your internet connection.";

  @override
  UpdateState build() {
    final j = ref.read(storageProvider).readJson(_key, (j) => (j as Map).cast<String, Object?>()) ?? const {};
    return UpdateState(
      lastCheck: DateTime.tryParse('${j['lastCheck']}'),
      autoCheck: j['autoCheck'] != false,
      skipped: j['skipped'] as String?,
      notified: j['notified'] as String?,
      seenVersion: j['seenVersion'] as String?,
      savedNotesVersion: j['notesVersion'] as String?,
      savedNotes: j['notes'] as String?,
    );
  }

  void _save() => ref.read(storageProvider).writeJson(_key, {
        'lastCheck': state.lastCheck?.toIso8601String(),
        'autoCheck': state.autoCheck,
        'skipped': state.skipped,
        'notified': state.notified,
        'seenVersion': state.seenVersion,
        'notesVersion': state.savedNotesVersion,
        'notes': state.savedNotes,
      });

  void setAutoCheck(bool v) {
    state = state.copyWith(autoCheck: v);
    _save();
  }

  void skip(String version) {
    analytics.event('update_skip', {'version': version});
    state = state.copyWith(skipped: () => version);
    _save();
  }

  /// Background check at startup: at most once a day, and a notification
  /// the first time a new version is seen.
  Future<void> autoCheck() async {
    if (!updatesSupported) return;
    await _loadVersion();
    if (state.seenVersion == null && state.currentVersion.isNotEmpty) {
      // First run: nothing to announce.
      state = state.copyWith(seenVersion: state.currentVersion);
      _save();
    }
    final storage = ref.read(storageProvider);
    if (state.justUpdated && storage.readJson('updateLogged', (j) => j as String) != state.currentVersion) {
      analytics.event('app_updated', {'version': state.currentVersion, 'from': state.seenVersion});
      storage.writeJson('updateLogged', state.currentVersion);
    }
    if (state.justUpdated && installsInApp) {
      // The APK that was just installed is no longer needed.
      unawaited(ApkInstaller.clear().catchError((_) {}));
    }
    if (!state.autoCheck) return;
    final last = state.lastCheck;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) {
      // Still learn our own version for the About screen.
      await _loadVersion();
      return;
    }
    await check();
    final u = state.pending;
    if (u != null && state.notified != u.version) {
      analytics.event('update_found', {'version': u.version, 'current': state.currentVersion});
      state = state.copyWith(notified: u.version);
      _save();
      try {
        await ref.read(notificationBackendProvider).showNow(
              'Amud ${u.version} is available',
              'Tap to see what\'s new and download the update.',
              route: '/update',
              id: 998,
            );
      } catch (e) {
        debugPrint('update notification failed: $e');
      }
    }
  }

  /// The user has seen (or dismissed) what's new in this version.
  void markSeen() {
    if (state.currentVersion.isEmpty) return;
    state = state.copyWith(seenVersion: state.currentVersion);
    _save();
  }

  /// Release notes for the running version: saved when the update was
  /// found, otherwise fetched from its GitHub release.
  Future<void> loadInstalledNotes() async {
    await _loadVersion();
    final v = state.currentVersion;
    if (v.isEmpty || state.installedNotes != null) return;
    if (state.savedNotesVersion == v && (state.savedNotes ?? '').isNotEmpty) {
      state = state.copyWith(installedNotes: () => state.savedNotes);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$updateRepo/releases/tags/v$v'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final notes = ((jsonDecode(res.body) as Map<String, dynamic>)['body'] as String?)?.trim() ?? '';
      state = state.copyWith(installedNotes: () => notes, savedNotesVersion: v, savedNotes: notes);
      _save();
    } catch (_) {}
  }

  String? _apk;

  /// Downloads the update and opens Android's install prompt. If installs
  /// from this app aren't allowed yet, opens that setting; [resumed] then
  /// carries on when the user comes back.
  Future<void> downloadAndInstall() async {
    final info = state.available;
    if (info?.downloadUrl == null || state.downloading != null) return;
    state = state.copyWith(downloading: () => 0, error: () => null);
    analytics.event('update_download', {'version': info!.version, 'status': 'start'});
    try {
      _apk = await ApkInstaller.download(info.downloadUrl!, info.version,
          size: info.downloadSize,
          sha256: info.sha256,
          onProgress: (p) => state = state.copyWith(downloading: () => p));
      state = state.copyWith(downloading: () => null);
      analytics.event('update_download', {'version': info.version, 'status': 'done'});
      await _install();
    } catch (e) {
      analytics.event('update_download', {'version': info.version, 'status': 'failed', 'error': e.runtimeType.toString()});
      state = state.copyWith(downloading: () => null, error: () => "The update couldn't be downloaded: $e");
    }
  }

  Future<void> _install() async {
    if (!await ApkInstaller.canInstall()) {
      state = state.copyWith(needsPermission: true);
      await ApkInstaller.openInstallSettings();
      return;
    }
    state = state.copyWith(needsPermission: false);
    try {
      await ApkInstaller.install(_apk!);
    } catch (e) {
      state = state.copyWith(error: () => "The installer couldn't be opened: $e");
    }
  }

  /// The app is back in the foreground, maybe from the install setting.
  Future<void> resumed() async {
    if (state.needsPermission && _apk != null && await ApkInstaller.canInstall()) await _install();
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
              sha256: (asset?['digest'] as String?)?.startsWith('sha256:') == true
                  ? (asset!['digest'] as String).substring(7)
                  : null,
            )
          : null;
      state = state.copyWith(
        checking: false,
        available: () => info,
        lastCheck: DateTime.now(),
        // Kept to show as "What's new" once this version is installed.
        savedNotesVersion: info?.version,
        savedNotes: info?.notes,
      );
      _save();
      return info;
    } on http.ClientException {
      // DNS/socket failures: no connection (or GitHub unreachable).
      state = state.copyWith(checking: false, error: () => _offline);
      return null;
    } on TimeoutException {
      state = state.copyWith(checking: false, error: () => _offline);
      return null;
    } catch (e) {
      state = state.copyWith(checking: false, error: () => '$e');
      return null;
    }
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
