import 'package:flutter_riverpod/flutter_riverpod.dart';
export 'web_integrations_stub.dart'
    if (dart.library.js_interop) 'web_integrations_web.dart';

final pendingSharedNoteProvider = StateProvider<Map<String, String>?>(
  (ref) => null,
);
