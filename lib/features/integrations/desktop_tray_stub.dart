class DesktopTray {
  final void Function(String) navigate;
  DesktopTray(this.navigate);
  Future<void> update(bool enabled, Map<String, Object?>? entry) async {}
  Future<void> dispose() async {}
}
