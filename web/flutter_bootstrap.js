{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: the app's own sw.js (see index.html) is the
// only service worker. Flutter's flutter_service_worker.js is now a stub
// that unregisters itself and reloads every tab; registering it at the
// same scope as sw.js made the two replace each other in a reload loop.
_flutter.loader.load();
