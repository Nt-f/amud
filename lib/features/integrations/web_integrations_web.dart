import 'dart:convert';
import 'dart:js_interop';

@JS('amudWeb.takeSharedNote')
external JSString? _takeSharedNote();
@JS('amudWeb.badge')
external JSPromise<JSAny?> _badge(JSNumber count);
@JS('amudWeb.enablePush')
external JSPromise<JSBoolean> _enablePush();
@JS('amudWeb.disablePush')
external JSPromise<JSAny?> _disablePush();
@JS('amudWeb.pushEnabled')
external JSPromise<JSBoolean> _pushEnabled();
@JS('amudWeb.pushAvailable')
external JSPromise<JSBoolean> _pushAvailable();
@JS('amudWeb.submitPlan')
external JSPromise<JSBoolean> _submitPlan(JSString plan);

Future<Map<String, String>?> takeSharedNote() async {
  final value = _takeSharedNote()?.toDart;
  if (value == null) return null;
  return (jsonDecode(value) as Map).cast<String, String>();
}

Future<void> updateOmerBadge(int count) async {
  await _badge(count.toJS).toDart;
}

Future<bool> enableWebPush() async => (await _enablePush().toDart).toDart;
Future<void> disableWebPush() async {
  await _disablePush().toDart;
}

Future<bool> webPushEnabled() async => (await _pushEnabled().toDart).toDart;
Future<bool> webPushAvailable() async => (await _pushAvailable().toDart).toDart;
Future<bool> submitPushPlan(List<Map<String, Object?>> plan) async =>
    (await _submitPlan(jsonEncode(plan).toJS).toDart).toDart;
