import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/l10n.dart';
import '../home/card_registry.dart';
import '../home/today.dart';
import '../zmanim/zman_catalog.dart';
import 'js_card.dart';
import 'js_runtime.dart';

class GalleryCard {
  final String id, title, description, author, script;
  const GalleryCard(
    this.id,
    this.title,
    this.description,
    this.author,
    this.script,
  );
  factory GalleryCard.fromJson(Map<String, Object?> j) {
    final card = GalleryCard(
      j['id'] as String,
      j['title'] as String,
      j['description'] as String,
      j['author'] as String,
      j['script'] as String,
    );
    if (card.id.isEmpty ||
        card.title.length > 160 ||
        card.script.length > 64000) {
      throw const FormatException('Invalid card entry');
    }
    return card;
  }
}

List<GalleryCard> parseCardGallery(String source) {
  final decoded = jsonDecode(source) as Map;
  if (decoded['version'] != 1) {
    throw const FormatException('Unsupported gallery version');
  }
  final cards = decoded['cards'] as List;
  if (cards.length > 100) {
    throw const FormatException('A gallery may contain at most 100 cards');
  }
  return cards
      .map((c) => GalleryCard.fromJson((c as Map).cast<String, Object?>()))
      .toList();
}

class CardGalleryScreen extends ConsumerStatefulWidget {
  const CardGalleryScreen({super.key});
  @override
  ConsumerState<CardGalleryScreen> createState() => _CardGalleryScreenState();
}

class _CardGalleryScreenState extends ConsumerState<CardGalleryScreen> {
  final _url = TextEditingController();
  List<GalleryCard>? _cards;
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _loadBundled();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _loadBundled() async {
    try {
      final cards = parseCardGallery(
        await rootBundle.loadString('assets/integrations/cards.json'),
      );
      if (mounted) {
        setState(() {
          _cards = cards;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadIndex() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      setState(() => _error = 'Enter an HTTPS JSON index URL.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri)..followRedirects = false)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw FormatException('Index returned HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 10),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('Index exceeds 1 MB');
        }
      }
      final cards = parseCardGallery(utf8.decode(bytes));
      if (mounted) setState(() => _cards = cards);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _preview(GalleryCard card) async {
    final contextJson = jsonEncode(
      ref
          .read(todaySnapshotProvider)
          .toJsContext(ref.read(zmanResolverProvider)),
    );
    final result = ref.read(jsRuntimeProvider).render(card.script, contextJson);
    final install = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(card.title),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${card.author} · ${card.description}'),
                FutureBuilder<JsCardResult>(
                  future: result,
                  builder: (_, snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final value = snapshot.data!;
                    return value.ok
                        ? DeclarativeCard(
                            spec: value.value,
                            fallbackTitle: card.title,
                          )
                        : Text(value.error!);
                  },
                ),
                ExpansionTile(
                  title: Text(context.tr('View script')),
                  children: [
                    SelectableText(
                      card.script,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  context.tr(
                    'Scripts can fetch HTTPS data. Install cards from authors you trust.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.tr('Install card')),
          ),
        ],
      ),
    );
    if (install == true) {
      ref
          .read(dashboardProvider.notifier)
          .add(
            CardConfig(
              id: 'gallery-${DateTime.now().microsecondsSinceEpoch}',
              type: 'customJs',
              span: 2,
              settings: {
                'title': card.title,
                'script': card.script,
                'galleryId': card.id,
              },
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Card added to Home'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Card gallery'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.tr(
            'Browse bundled examples or load a community index from a GitHub raw JSON URL.',
          ),
        ),
        TextField(
          controller: _url,
          decoration: InputDecoration(
            labelText: context.tr('Community index URL'),
            hintText: 'https://raw.githubusercontent.com/…/cards.json',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _loading ? null : _loadIndex,
              child: Text(context.tr('Load index')),
            ),
            TextButton(
              onPressed: _loadBundled,
              child: Text(context.tr('Bundled examples')),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final card in _cards ?? const <GalleryCard>[])
          ListTile(
            title: Text(card.title),
            subtitle: Text('${card.description}\n${card.author}'),
            trailing: const Icon(Icons.add),
            onTap: () => _preview(card),
          ),
      ],
    ),
  );
}
