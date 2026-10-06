// Local-only Whisper inference. Runtime assets are precached with the PWA.
var module = {};
let engine;
let recognizer;
let recognitionLanguage;

self.onmessage = async ({data}) => {
  try {
    if (!engine) {
      const runtime = new URL(data.runtime);
      if (runtime.origin !== self.location.origin) throw new Error('Invalid runtime origin');
      importScripts(new URL('sherpa-onnx-wasm-web.js', runtime).href,
                    new URL('sherpa-onnx-asr.js', runtime).href);
      const response = await fetch(new URL('sherpa-onnx-wasm-web.wasm', runtime));
      if (!response.ok) throw new Error('Offline speech runtime unavailable');
      engine = await SherpaOnnx({wasmBinary: await response.arrayBuffer()});
      for (const [name, bytes] of Object.entries(data.files)) {
        engine.FS.writeFile('/' + name, new Uint8Array(bytes));
      }
    }
    const language = data.language || '';
    if (!recognizer || recognitionLanguage !== language) {
      if (recognizer) recognizer.free();
      recognizer = new OfflineRecognizer({
        featConfig: {sampleRate: 16000, featureDim: 80},
        modelConfig: {
          whisper: {
            encoder: '/small-encoder.int8.onnx', decoder: '/small-decoder.int8.onnx',
            language, task: 'transcribe', tailPaddings: -1,
          },
          tokens: '/small-tokens.txt', modelType: 'whisper',
          numThreads: 1, provider: 'cpu', debug: 0,
        },
        decodingMethod: 'greedy_search',
      }, engine);
      if (!recognizer.handle) throw new Error('Unable to load voice model');
      recognitionLanguage = language;
    }
    const stream = recognizer.createStream();
    try {
      stream.acceptWaveform(16000, data.samples);
      recognizer.decode(stream);
      self.postMessage({text: recognizer.getResult(stream).text.trim()});
    } finally {
      stream.free();
    }
  } catch (error) {
    self.postMessage({error: String(error)});
  }
};
