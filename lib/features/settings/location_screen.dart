import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../core/analytics.dart';

bool _inIsrael(double lat, double lon) => lat > 29.45 && lat < 33.35 && lon > 34.2 && lon < 35.9;

class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  String _query = '';
  bool _locating = false;
  String? _error;

  void _choose(SavedLocation l, {String method = 'list'}) {
    analytics.event('location_set', {'method': method, 'country': l.countryCode, 'in_israel': l.il});
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(location: l));
    Navigator.of(context).maybePop();
  }

  Future<void> _useGps() async {
    setState(() => (_locating = true, _error = null));
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      String tzid;
      try {
        tzid = (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.getLocation(tzid);
      } catch (_) {
        tzid = 'UTC';
      }
      final il = _inIsrael(pos.latitude, pos.longitude);
      _choose(SavedLocation(
        name: 'Current location',
        latitude: pos.latitude,
        longitude: pos.longitude,
        elevation: pos.altitude > 0 ? pos.altitude : 0,
        tzid: il ? 'Asia/Jerusalem' : tzid,
        countryCode: il ? 'IL' : null,
        il: il,
      ), method: 'gps');
    } catch (e) {
      analytics.event('location_gps_failed', {'error': e.runtimeType.toString()});
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = Location.classicCities()..sort((a, b) => a.getName()!.compareTo(b.getName()!));
    final filtered = cities.where((c) => c.getName()!.toLowerCase().contains(_query.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Location'))),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _locating ? null : _useGps,
                icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator.adaptive(strokeWidth: 2)) : const Icon(Icons.my_location),
                label: Text(context.tr('Use my location')),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(onPressed: () => _manual(context), icon: const Icon(Icons.edit_location_alt_outlined), label: Text(context.tr('Manual'))),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.tr('Your browser will ask for permission to share your location.'), style: const TextStyle(fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: context.tr('Search cities')),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        for (final c in filtered)
          ListTile(
            title: Text(c.getName()!),
            subtitle: Text('${c.getCountryCode()} · ${c.getTzid()}'),
            onTap: () => _choose(SavedLocation.fromLocation(c)),
          ),
      ]),
    );
  }

  Future<void> _manual(BuildContext context) async {
    final cur = ref.read(settingsProvider).location;
    final name = TextEditingController(text: cur.name);
    final lat = TextEditingController(text: '${cur.latitude}');
    final lon = TextEditingController(text: '${cur.longitude}');
    final elev = TextEditingController(text: '${cur.elevation.round()}');
    var tzid = cur.tzid;
    var il = cur.il;
    final zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: context.tr('Name'))),
                TextField(controller: lat, decoration: InputDecoration(labelText: context.tr('Latitude')), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                TextField(controller: lon, decoration: InputDecoration(labelText: context.tr('Longitude')), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
                TextField(controller: elev, decoration: InputDecoration(labelText: context.tr('Elevation (m)')), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: tzid),
                  optionsBuilder: (v) => zones.where((z) => z.toLowerCase().contains(v.text.toLowerCase())).take(30),
                  onSelected: (v) => tzid = v,
                  fieldViewBuilder: (c, ctrl, focus, submit) =>
                      TextField(controller: ctrl, focusNode: focus, decoration: InputDecoration(labelText: context.tr('Time zone'))),
                ),
                SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(context.tr('Israel customs')), value: il, onChanged: (v) => setSt(() => il = v)),
                FilledButton(
                  onPressed: () {
                    final la = double.tryParse(lat.text);
                    final lo = double.tryParse(lon.text);
                    if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180 || !zones.contains(tzid)) return;
                    Navigator.pop(ctx);
                    _choose(SavedLocation(
                      name: name.text.trim().isEmpty ? 'Custom' : name.text.trim(),
                      latitude: la,
                      longitude: lo,
                      elevation: double.tryParse(elev.text) ?? 0,
                      tzid: tzid,
                      il: il,
                      countryCode: il ? 'IL' : null,
                    ));
                  },
                  child: Text(context.tr('Save')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
