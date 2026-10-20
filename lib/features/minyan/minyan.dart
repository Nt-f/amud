import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
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
    const title = 'Find a minyan';
    final link = Icon(Icons.open_in_new, size: 16, color: theme.colorScheme.outline);
    final near = context.tr('Minyanim near {place}', {'place': loc.getShortName() ?? ''});
    final small = theme.textTheme.bodySmall;
    return LayoutBuilder(builder: (context, c) {
      // The link beside the card's name, or where that would leave it on a
      // line of its own (a compact card on a narrow phone), beside GoDaven.
      final inHeading = CardFrame.fitsBesideTitle(context, title, 16, cardWidth: c.maxWidth);
      final room = c.maxWidth - 2 * CardFrame.padding;
      return CardFrame(
        title: title,
        icon: Icons.groups_outlined,
        trailing: inHeading ? link : null,
        onTap: () => launchUrl(p.webSearchUri(loc.latitude, loc.longitude), mode: LaunchMode.externalApplication),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Shrinks rather than breaking the name in a compact card.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(p.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            if (!inHeading) ...[const SizedBox(width: 6), link],
          ]),
          // Set at least as wide as its longest word and shrunk to fit, so a
          // long place name never breaks mid-word.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: math.max(room, widestWord(context, [near], small).ceilToDouble()),
              child: Text(near, style: small, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
      );
    });
  }
}
