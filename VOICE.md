# Offline voice navigation

**Currently disabled:** microphone entry points and the `/voice` route are
removed. The implementation is retained for future evaluation. The instructions
below describe its behavior when enabled.

Tap the microphone beside a search field or in a siddur/Torah reader. It is
also available in Settings → Widgets, shortcuts & voice. Download the
multilingual Whisper small INT8 model once (375,485,327 bytes, about 375 MB).
The download is optional and separate from the application. Afterward,
recording, transcription and section matching run on the device with no
speech service, API key or network connection. Recordings are held in memory
and discarded after recognition; they are not uploaded or saved.

The microphone records at most twelve seconds. Tap Stop when finished.
The transcript can be edited, and commands can also be typed without a model
or microphone permission. Automatic language detection is the default;
Hebrew and English can be selected explicitly.

Examples:

- `open Mincha` / `פתח מנחה`
- `open Shema in Shacharit` / `פתח שמע בשחרית`
- `פתח Shemoneh Esrei בשחרית`
- `פתח עלינו`
- `Kitzur סימן three סעיף two`
- `פתח קיצור שולחן ערוך סימן עשרים ושלוש סעיף ארבע`
- `תהילים פרק עשרים ושלוש`

Siddur matching uses the existing complete section index: Hebrew and English
titles, prayer aliases, transliteration matching, and parent service names.
Unambiguous strong matches open directly; ambiguous ones show the book and
service for selection. Torah numeric commands currently address Kitzur
Shulchan Aruch, the library's available work. That book must already be
downloaded. Other Torah works remain the app's existing placeholders.

## Platforms

Android, iOS, macOS, Windows and Linux use sherpa-onnx native inference in a
Dart isolate. Android and Apple applications request microphone access only
when recording starts. Linux requires the recorder package's runtime tools:
`parecord`, `pactl` and `ffmpeg` (typically `pulseaudio-utils` and `ffmpeg`).

Web/PWA uses the same model in a dedicated WebAssembly worker. Runtime JS,
WASM and audio worklet files are bundled and included by the existing offline
service worker generator. Model weights live in their own browser cache,
preserved across application updates. Microphone access requires HTTPS or
localhost. Browser storage eviction, private browsing or clearing site data
can remove the downloaded model. Inference needs substantial free memory,
especially on mobile browsers.

Weights are pinned to upstream revision
`8f3c18b358db4d1f2fc1eae49d75cd20989e4309`. Every downloaded file is checked
against its expected size and SHA-256 before the installation is marked ready.
Source: [sherpa-onnx Whisper small model](https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small).

## Accuracy and validation

Multilingual recognition does **not** establish reliable Hebrew–English code
switching. The small model misrecognized a locally synthesized mixed command,
including with Hebrew forced. Hebrew title matching cannot recover speech
that was transcribed incorrectly. Real spoken commands, Hebrew accents and
transliteration variants need device testing before treating this as reliable
hands-free navigation; the editable transcript and section choices are the
fallback.

Native Linux inference and the actual browser worker successfully transcribed
the maintainer's sample recording. Command and matching tests cover Hebrew,
English, mixed transcripts, spoken numbers, Hebrew numeral notation, service
disambiguation and preferred-siddur selection. These tests verify navigation,
not spoken recognition accuracy.

To evaluate a real recording independently of the microphone UI:

```sh
dart run tool/voice/transcribe.dart MODEL_DIRECTORY RECORDING.wav [LIB_DIRECTORY] [LANGUAGE]
```

The model directory contains `small-encoder.int8.onnx`,
`small-decoder.int8.onnx` and `small-tokens.txt`; the WAV must be mono 16 kHz.
`LANGUAGE` may be `he`, `en`, or omitted for automatic detection.
