Future<String> download(String url, String version, {int? size, String? sha256, void Function(double)? onProgress}) =>
    throw UnsupportedError('In-app install is Android only');
Future<bool> canInstall() async => false;
Future<void> openInstallSettings() async {}
Future<void> install(String path) => throw UnsupportedError('In-app install is Android only');
Future<void> clear() async {}
