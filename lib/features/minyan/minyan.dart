import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
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

/// Compact card; tapping it opens the provider to search nearby.
class MinyanCard extends ConsumerWidget {
  const MinyanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(minyanProvidersProvider).first;
    final loc = ref.watch(locationProvider);
    final theme = Theme.of(context);
    return CardFrame(
      title: 'Find a minyan',
      icon: Icons.groups_outlined,
      trailing: Icon(Icons.open_in_new, size: 16, color: theme.colorScheme.outline),
      onTap: () => launchUrl(p.webSearchUri(loc.latitude, loc.longitude), mode: LaunchMode.externalApplication),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(context.tr('Minyanim near {place}', {'place': loc.getShortName() ?? ''}),
            style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
