import 'apk_installer_stub.dart' if (dart.library.io) 'apk_installer_io.dart' as impl;

/// Downloads a release APK and hands it to Android's installer, so updates
/// install from inside the app instead of through the browser.
abstract final class ApkInstaller {
  /// Downloads [url] into the app's update folder and returns the file's
  /// path. [onProgress] gets 0–1 when the size is known. A file already
  /// downloaded for [version] is reused; [sha256] (hex), if given, is checked.
  static Future<String> download(String url, String version,
          {int? size, String? sha256, void Function(double)? onProgress}) =>
      impl.download(url, version, size: size, sha256: sha256, onProgress: onProgress);

  /// Whether the user has allowed this app to install apps (Android 8+).
  static Future<bool> canInstall() => impl.canInstall();

  /// Opens the "Install unknown apps" setting for this app.
  static Future<void> openInstallSettings() => impl.openInstallSettings();

  /// Shows the system install prompt for a downloaded APK.
  static Future<void> install(String path) => impl.install(path);

  /// Deletes downloaded APKs (once they're installed or out of date).
  static Future<void> clear() => impl.clear();
}
