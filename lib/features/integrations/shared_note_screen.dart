import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n.dart';
import '../home/card_registry.dart';
import 'web_integrations.dart';

class SharedNoteScreen extends ConsumerWidget {
  const SharedNoteScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(pendingSharedNoteProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Shared note'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: note == null
            ? Text(
                context.tr(
                  'Share text to Amud from another app to create a note card.',
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note['title']!.isEmpty
                        ? context.tr('Note')
                        : note['title']!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(note['text']!),
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('Add note to Home')),
                    onPressed: () {
                      ref
                          .read(dashboardProvider.notifier)
                          .add(
                            CardConfig(
                              id: 'share-${DateTime.now().microsecondsSinceEpoch}',
                              type: 'note',
                              span: 2,
                              settings: {
                                'title': note['title']!.isEmpty
                                    ? 'Note'
                                    : note['title'],
                                'text': note['text'],
                              },
                            ),
                          );
                      ref.read(pendingSharedNoteProvider.notifier).state = null;
                      context.go('/');
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
