import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../home/cards/card_frame.dart';

/// A scheduled minyan at a shul.
class Minyan {
  final String shul;
  final String address;
  final String prayer;
  final DateTime time;
  final double? distanceKm;
  final String? nusach;
  final String? url;
  const Minyan({required this.shul, required this.address, required this.prayer, required this.time, this.distanceKm, this.nusach, this.url});
}

/// Source of minyan listings. Implementations are pluggable so that
/// GoDaven (or a shul's own feed) can be added without touching the UI.
abstract class MinyanProvider {
  String get name;

  /// Whether the provider can currently be queried from the app.
  bool get available;
  Future<List<Minyan>> search({required double latitude, required double longitude, double radiusKm = 5, DateTime? from, DateTime? to});

  /// A web page the user can open as a fallback.
  Uri webSearchUri(double latitude, double longitude);
}

/// Placeholder for GoDaven. GoDaven does not currently publish a public
/// API, so listings are not fetched; the card deep-links to the website
/// instead. When an API/partnership is available, implement [search]
/// here and flip [available].
class GoDavenProvider implements MinyanProvider {
  const GoDavenProvider();

  @override
  String get name => 'GoDaven';

  @override
  bool get available => false;

  @override
  Future<List<Minyan>> search({required double latitude, required double longitude, double radiusKm = 5, DateTime? from, DateTime? to}) =>
      Future.error(UnsupportedError('GoDaven integration is not available yet'));

  @override
  Uri webSearchUri(double latitude, double longitude) => Uri.parse('https://godaven.com/');
}

final minyanProvidersProvider = Provider<List<MinyanProvider>>((ref) => const [GoDavenProvider()]);

class MinyanCard extends ConsumerWidget {
  const MinyanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(minyanProvidersProvider);
    final loc = ref.watch(locationProvider);
    final p = providers.first;
    final theme = Theme.of(context);
    return CardFrame(
      title: 'Find a minyan',
      icon: Icons.groups_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          p.available
              ? 'Minyanim near ${loc.getShortName()}'
              : '${p.name} integration is coming soon. Meanwhile, open ${p.name} to search minyanim near ${loc.getShortName()}.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => launchUrl(p.webSearchUri(loc.latitude, loc.longitude), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new),
          label: Text('Open ${p.name}'),
        ),
      ]),
    );
  }
}
