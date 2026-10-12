import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import 'core/content.dart';
import 'core/fonts.dart';
import 'core/providers.dart';
import 'core/storage.dart';
import 'features/home/card_registry.dart';
import 'features/wear/wear_app.dart';

/// The standalone Wear OS app: no phone, no account, no network. It computes
/// the date, zmanim and prayers on the watch with the same engine as the phone.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initHebcal();
  final storage = await Storage.open();
  Content.attach(storage);
  final container = ProviderContainer(overrides: [
    storageProvider.overrideWithValue(storage),
    cardRegistryProvider.overrideWithValue(CardRegistry()),
  ]);
  await container.read(fontsProvider.notifier).loadAll();
  runApp(UncontrolledProviderScope(container: container, child: const WearApp()));
}
