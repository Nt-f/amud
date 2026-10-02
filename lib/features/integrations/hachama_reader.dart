import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../core/focus_mode.dart';

/// Public-domain blessing text when the bundled siddur has no sun-blessing
/// section. Source: Berakhot 59b and the traditional blessing formula.
class HachamaReader extends ConsumerStatefulWidget {
  const HachamaReader({super.key});
  @override
  ConsumerState<HachamaReader> createState() => _HachamaReaderState();
}

class _HachamaReaderState extends ConsumerState<HachamaReader>
    with FocusModeReader {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      body: Column(
        children: [
          FocusModeBars(
            child: AppBar(title: Text(context.tr('Birkat HaChama'))),
          ),
          Expanded(
            child: FocusModeBody(
              child: DoubleTapListener(
                onDoubleTap: toggleFocusMode,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'בָּרוּךְ אַתָּה יְהוָה אֱלֹהֵינוּ מֶלֶךְ הָעוֹלָם עוֹשֵׂה מַעֲשֵׂה בְרֵאשִׁית.',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: settings.hebrewFont,
                        fontSize: 26 * settings.textScale,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.tr(
                        'The blessing of the sun · once every 28 years.',
                      ),
                    ),
                    const Text(
                      'Source: Berakhot 59b · traditional blessing text (public domain).',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
