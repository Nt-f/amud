import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'prayer_links.dart';

class DesktopTray with TrayListener {
  final void Function(String) navigate;
  bool _created = false;
  String? _last;
  DesktopTray(this.navigate);

  Future<void> update(bool enabled, Map<String, Object?>? entry) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    if (!enabled) {
      if (_created) {
        await trayManager.destroy();
        trayManager.removeListener(this);
        _created = false;
        _last = null;
      }
      return;
    }
    if (!_created) {
      await windowManager.ensureInitialized();
      final ext = Platform.isWindows ? 'ico' : 'png';
      await trayManager.setIcon('assets/integrations/tray.$ext');
      trayManager.addListener(this);
      _created = true;
    }
    final next = entry == null
        ? 'Open Amud to refresh zmanim'
        : '${entry['nextZman']} ${entry['nextZmanTime']}';
    if (_last == next) return;
    _last = next;
    await trayManager.setToolTip('Amud · $next');
    if (Platform.isMacOS) await trayManager.setTitle(next);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: '/zmanim', label: next),
          MenuItem.separator(),
          for (final prayer in prayerShortcuts.entries)
            MenuItem(key: '/pray/${prayer.key}', label: prayer.value),
          MenuItem.separator(),
          MenuItem(key: '/', label: 'Open Amud'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final route = menuItem.key;
    if (route == null) return;
    windowManager.show().then((_) => windowManager.focus());
    navigate(route);
  }

  Future<void> dispose() async {
    if (_created) {
      trayManager.removeListener(this);
      await trayManager.destroy();
      _created = false;
    }
  }
}
