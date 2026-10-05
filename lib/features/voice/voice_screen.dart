import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/search.dart';
import '../../core/settings.dart';
import '../search/search_sources.dart';
import '../siddur/prayer_catalog.dart';
import '../siddur/reader_screen.dart';
import '../siddur/siddur_providers.dart';
import '../torah/torah_library.dart';
import '../tehillim/tehillim_data.dart' show Portion, Passage;
import '../tehillim/tehillim_reader.dart';
import 'offline_voice.dart';
import 'voice_command.dart';
import 'voice_model.dart';
import 'voice_matches.dart';

class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});
  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  late final _backend = OfflineVoiceBackend(ref.read(storageProvider));
  StreamSubscription<Uint8List>? _audio;
  Timer? _limit;
  BytesBuilder _pcm = BytesBuilder(copy: false);
  bool _ready = false, _busy = false, _recording = false;

  /// Part of the model is in from a download that stopped.
  bool _partial = false;
  double? _progress;
  String? _message;
  String _query = '';
  String _language = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkModel();
  }

  Future<void> _checkModel() async {
    try {
      final ready = await _backend.ready();
      final partial = !ready && await _backend.size() > 0;
      if (mounted) {
        setState(() {
          _ready = ready;
          _partial = partial;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Unable to access voice model storage.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording) _cancelRecording();
  }

  void _cancelRecording() {
    _limit?.cancel();
    _recording = false;
    _audio?.cancel();
    _recorder.cancel();
    _pcm = BytesBuilder(copy: false);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _limit?.cancel();
    _audio?.cancel();
    _recorder.dispose();
    _backend.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _message = null;
      _progress = 0;
    });
    try {
      await _backend.install((progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(
          () {
            _partial = true;
            _message =
                'Model download stopped. Check your connection and free storage, then continue: it picks up where it left off.';
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(
            () => _message =
                'Microphone access is needed for voice commands. You can also type below.',
          );
        }
        return;
      }
      if (!mounted) return;
      _pcm = BytesBuilder(copy: false);
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      _recording = true;
      _audio = stream.listen(
        (bytes) {
          if (!_recording) return;
          _pcm.add(bytes);
          if (_pcm.length >= 16000 * 2 * 12) _stop();
        },
        onError: (Object error) {
          _cancelRecording();
          if (mounted) {
            setState(
              () => _message =
                  'Recording failed. Check your microphone and try again.',
            );
          }
        },
      );
      _limit = Timer(const Duration(seconds: 12), _stop);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Unable to start the microphone on this device. You can also type below.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (!_recording || _busy) return;
    _limit?.cancel();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      await _recorder.stop();
      await _audio?.cancel();
      final samples = voicePcmSamples(_pcm.takeBytes());
      final energy = samples.fold<double>(
        0,
        (sum, sample) => sum + sample * sample,
      );
      if (samples.length < 3200 || math.sqrt(energy / samples.length) < 0.003) {
        if (mounted) {
          setState(
            () =>
                _message = 'No speech heard. Tap the microphone and try again.',
          );
        }
        return;
      }
      final transcript = await _backend.transcribe(
        samples,
        language: _language,
      );
      if (!mounted) return;
      _text.text = transcript;
      if (transcript.isEmpty) {
        setState(
          () => _message =
              'No speech recognized. Try again or type the section name.',
        );
      } else {
        await _openCommand(transcript);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Unable to recognize this recording. Try again; the model may need more memory on this device.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCommand(String text) async {
    final query = voiceQuery(text);
    setState(() {
      _query = query;
      _message = null;
    });
    final prayer = voicePrayer(query);
    if (prayer != null) {
      context.pushReplacement('/pray/$prayer');
      return;
    }
    final psalm = RegExp(
      r'^(?:tehillim|tehilim|psalm|psalms|תהלים|תהילים)\s+(?:(?:chapter|פרק)\s+)?(.+)$',
    ).firstMatch(query);
    if (psalm != null) {
      final chapter = voiceNumber(psalm[1]!);
      if (chapter != null && chapter >= 1 && chapter <= 150) {
        context.pushReplacement(
          tehillimReadPath(
            Portion('Tehillim $chapter', 'תהלים $chapter', [Passage(chapter)]),
          ),
        );
        return;
      }
    }
    final reference = kitzurVoiceReference(query);
    if (reference == null) {
      if (query.isEmpty) return;
      try {
        final index = await ref.read(prayerIndexProvider.future);
        final manifest = await ref.read(manifestProvider.future);
        final defaultBook = await ref.read(defaultBookProvider.future);
        if (!mounted || query != _query) return;
        final matches = voicePrayerMatches(
          query,
          index,
          bookSearchOrder(manifest, defaultBook),
        );
        // Only unambiguous, strong matches open automatically. Other matches
        // remain choices, with the service and siddur shown for each one.
        final strong = matches.where((match) => match.score < 10).toList();
        if (strong.length == 1) {
          final entry = strong.single.entry;
          context.pushReplacement(
            readerPath(entry.book, entry.node.id, standalone: true),
          );
        }
      } catch (_) {
        if (mounted) {
          setState(
            () =>
                _message = 'Unable to load siddur sections. Please try again.',
          );
        }
      }
      return;
    }
    final book = await ref.read(torahBookProvider(kitzur.id).future);
    if (!mounted) return;
    if (book == null) {
      setState(
        () => _message =
            'Download Kitzur Shulchan Aruch in the Torah library before opening a section offline.',
      );
      return;
    }
    final chapter = reference.chapter;
    if (chapter > book.length) {
      setState(() => _message = 'That siman is not in this book.');
      return;
    }
    final paragraph = reference.paragraph;
    final count = math.max(
      book.he[chapter - 1].length,
      chapter <= book.en.length ? book.en[chapter - 1].length : 0,
    );
    if (paragraph != null && paragraph > count) {
      setState(() => _message = 'That seif is not in this siman.');
      return;
    }
    context.pushReplacement(
      Uri(
        path: '/torah/halacha/kitzur/read',
        queryParameters: {
          'siman': '$chapter',
          if (paragraph != null) ...{'from': '$paragraph', 'to': '$paragraph'},
        },
      ).toString(),
    );
  }

  List<SearchHit> _prayers(List<PrayerEntry> index, List<String> order) {
    final found = voicePrayerMatches(_query, index, order);
    return [
      for (final match in found)
        SearchHit(
          icon: Icons.menu_book_outlined,
          title: '${match.entry.node.en} · ${match.entry.node.he}',
          subtitle:
              '${match.entry.book}${match.entry.path.isEmpty ? '' : ' › ${match.entry.path.map((p) => p.en).join(' › ')}'}',
          score: match.score,
          open: (context) => context.pushReplacement(
            readerPath(match.entry.book, match.entry.node.id, standalone: true),
          ),
        ),
    ].take(20).toList();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(prayerIndexProvider);
    final manifest = ref.watch(manifestProvider);
    final defaultBook = ref.watch(defaultBookProvider);
    final order = manifest.hasValue && defaultBook.hasValue
        ? bookSearchOrder(manifest.requireValue, defaultBook.requireValue)
        : <String>[];
    final query = SearchQuery(_query);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Voice navigation'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('Speak in Hebrew, English, or both.')),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Try “open Shema”, “פתח עלינו”, or “Kitzur סימן three סעיף two”.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Recordings stay on this device. Mixed-language recognition can make mistakes; edit the transcript or choose a matching section.',
            ),
          ),
          if (!_ready) ...[
            const SizedBox(height: 16),
            Text(
              context.tr(
                'Download the multilingual voice model once (375 MB), then use voice offline.',
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _install,
              icon: const Icon(Icons.download),
              label: Text(context.tr(_partial ? 'Continue download' : 'Download voice model')),
            ),
          ],
          if (_progress != null) ...[
            LinearProgressIndicator(value: _progress),
            Text('${(_progress! * 100).round()}%'),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: InputDecoration(
              labelText: context.tr('Recognition language'),
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(context.tr('Automatic'))),
              const DropdownMenuItem(value: 'he', child: Text('עברית')),
              const DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: _busy || _recording
                ? null
                : (language) => setState(() => _language = language ?? ''),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: !_ready || _busy
                  ? null
                  : _recording
                  ? _stop
                  : _start,
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(
                context.tr(_recording ? 'Stop & open' : 'Speak a command'),
              ),
            ),
          ),
          if (_recording)
            Text(
              context.tr(
                'Listening… Tap Stop when finished (up to 12 seconds).',
              ),
              textAlign: TextAlign.center,
            ),
          if (_busy && _progress == null) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            Text(
              context.tr('Processing on this device…'),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            enabled: !_busy && !_recording,
            decoration: InputDecoration(
              labelText: context.tr('Command or section name'),
              suffixIcon: IconButton(
                tooltip: context.tr('Open'),
                onPressed: _busy || _recording
                    ? null
                    : () => _openCommand(_text.text),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onSubmitted: _openCommand,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.tr(_message!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_query.isNotEmpty) ...[
            if (index.isLoading) const LinearProgressIndicator(),
            if (index.hasError)
              Text(
                context.tr('Unable to load siddur sections. Please try again.'),
              ),
            if (index.hasValue)
              SearchResults(
                query: _query,
                hebrewFont: ref.watch(settingsProvider).hebrewFont,
                groups: [
                  (context.tr('Siddur'), _prayers(index.requireValue, order)),
                  ...torahResults(context, ref, query),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
