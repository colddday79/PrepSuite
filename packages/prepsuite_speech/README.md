# prepsuite_speech

Offline speech for PrepSuite (Android + iPhone). Everything runs on the phone; no audio leaves the device.

- **Speech-to-text**: streaming Zipformer transducer via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 1.13.8, live partial text while recording, final transcript with per-word start/end times.
- **Delivery metrics**: pure-Dart `DeliveryAnalyzer` (pace, pauses, fillers, loudness, trailing off, pitch variation).
- **Interviewer voice**: the owner's Piper voice "Norman" (en_US, medium), synthesised offline one sentence at a time.

## Setup

1. Create the model files. They are about 135 MB and are not in git:

   ```sh
   tools/voice/fetch_models.sh        # ASR=librispeech for the Apache-2.0 fallback model
   ```

   The script downloads the ASR model and `espeak-ng-data` from the official k2-fsa/sherpa-onnx releases, checking SHA-256. It converts Norman from `~/Downloads/en_US-norman-medium.onnx(.json)` using sherpa-onnx's documented Piper recipe, which needs `onnx` in `tools/voice/.venv`. It then writes everything to `lib/assets/models/`.

2. Declare the assets in the **app's** `pubspec.yaml`. The files live in this package's `lib/`, so the app includes them under `packages/prepsuite_speech/...`:

   ```yaml
   flutter:
     assets:
       - packages/prepsuite_speech/assets/models/manifest.json
       - packages/prepsuite_speech/assets/models/asr/encoder.onnx
       - packages/prepsuite_speech/assets/models/asr/decoder.onnx
       - packages/prepsuite_speech/assets/models/asr/joiner.onnx
       - packages/prepsuite_speech/assets/models/asr/tokens.txt
       - packages/prepsuite_speech/assets/models/tts/en_US-norman-medium.onnx
       - packages/prepsuite_speech/assets/models/tts/tokens.txt
       - packages/prepsuite_speech/assets/models/tts/espeak-ng-data/phontab
       - packages/prepsuite_speech/assets/models/tts/espeak-ng-data/phonindex
       - packages/prepsuite_speech/assets/models/tts/espeak-ng-data/phondata
       - packages/prepsuite_speech/assets/models/tts/espeak-ng-data/phondata-manifest
       - packages/prepsuite_speech/assets/models/tts/espeak-ng-data/intonations
       - packages/prepsuite_speech/assets/models/tts/espeak-ng-data/en_dict
       - packages/prepsuite_speech/assets/models/tts/espeak-ng-data/lang/gmw/en
   ```

3. Permissions:
   - Android: add `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`. The minimum SDK is 24, which is Flutter's default.
   - iOS: add `NSMicrophoneUsageDescription` to `Info.plist`. iOS 13 or later is required.
   - `start()` requests the microphone permission and returns `false` if it is denied.

## Use

```dart
import 'package:prepsuite_speech/prepsuite_speech.dart';

// Once, e.g. on a splash screen. The first run copies about 135 MB (2–3 s on the emulator); later runs return at once.
await SpeechModels.ensureReady(onProgress: (p) => setState(() => progress = p));

final capture = OfflineSpeechCapture();   // warmUp() preloads (~1.3 s)
final voice = NormanVoice();              // warmUp() preloads (~0.6 s)

await voice.speak('What job are you preparing for?');   // completes when playback ends
await capture.start(maxDuration: const Duration(seconds: 10));
capture.partialText.listen(showCaption);   // updates about every 1.3 s
capture.level.listen(drivePresence);       // 0..1, ~20 Hz
final result = await capture.stop();       // CaptureResult? (null on failure)
// result.transcript.text / .words (TimedWord ms), result.metrics.toJson() -> send to the coach
```

- **Threading.** Call everything from the UI isolate. Recognition, WAV writing, metrics, and speech synthesis each run in their own background isolate, and every call is async. `transcribeFile(path)` handles WAV files (PCM16/24/32 or float, any rate, stereo is down-mixed).
- **Recording while Norman speaks.** Call `voice.stop()` before `capture.start()`, or the microphone will record Norman. When recording stops on its own at `maxDuration`, `OfflineSpeechCapture.onMaxDuration` fires and `stop()` returns the result.
- **Recordings** are stored in app-private support storage at `prepsuite_speech/recordings/answer_<ms>.wav`: 16 kHz mono PCM16, taken from one microphone stream that feeds both the recogniser and the file. Pass `recordingsDir:` to choose another folder. Deleting files is the app's job.
- **Errors.** `speak()` throws if the voice cannot load; show the text instead. `SpeechModels.ensureReady()` throws `SpeechModelsMissing` when the assets are not bundled.

## Metrics (`DeliveryMetrics.toJson()`)

The analyser uses 25 ms frames. A frame counts as voiced when it is above an adaptive energy threshold: `max(floor+10 dB, peak−35 dB, −60 dBFS)`, or `peak−20 dB` when the recording has almost no silence.

| key | meaning |
|---|---|
| `duration_s` | Length of the whole recording. |
| `words`, `wpm` | Recognised words (fillers included) per minute of the speaking span, from the first to the last voiced frame. |
| `pauses_over_1s`, `longest_pause_s` | Silences between voiced regions; silence at the start and end is ignored. |
| `speech_ratio` | Share of the speaking span not spent in silences of 200 ms or longer. |
| `fillers`, `filler_count` | Counted from the transcript: um, uh (incl. "ah"), er, like*, you know*, sort of*, kind of*, I mean*, basically, actually. Words marked * are counted only when used as fillers, judged by simple rules (see `lib/src/fillers.dart`). |
| `loudness_db_mean`, `loudness_db_sd` | dBFS over voiced frames. These depend on the microphone and how far away it is, so compare them only within one user. |
| `trailing_off` | The last 20% of voiced frames is at least 4 dB quieter than the rest. |
| `pitch_hz_mean`, `pitch_semitone_sd` | YIN, 60–400 Hz, smoothed with a median filter, with octave jumps removed. Null when fewer than 0.5 s is pitched. |
| `monotone` | True when the pitch SD is below 1.5 semitones. Null when less than 2 s is voiced. |

## Models and licences

| file | size | source | licence |
|---|---|---|---|
| `asr/*` Kroko EN streaming Zipformer (int8, 1.28 s chunks) | 71 MB | `sherpa-onnx-streaming-zipformer-en-kroko-2025-08-06` (asr-models release) | Kroko "community" model under CC-BY-SA. Attribution is required, and Kroko pitches it at free tiers, selling commercial models. `ASR=librispeech` swaps in the Apache-2.0 `sherpa-onnx-streaming-zipformer-en-2023-06-26` (int8, 71 MB). It is less accurate and drops most fillers. |
| `tts/en_US-norman-medium.onnx` + `tokens.txt` | 63.5 MB | Owner's file (matches the rhasspy/piper-voices SHA-256) with sherpa-onnx metadata added | piper-voices repo licence: MIT. Dataset: LibriVox recordings (public domain), trained by Bryce Beattie. |
| `tts/espeak-ng-data` (English subset) | 0.8 MB | `espeak-ng-data.tar.bz2` (tts-models release) | espeak-ng: GPL-3.0. The phonemiser compiled into sherpa-onnx's native library is also espeak-ng, so check distribution with counsel. |

The English-only `espeak-ng-data` subset gives bit-identical Norman audio to the full 18 MB set. This was tested with noise disabled.

Engine: sherpa-onnx (Apache-2.0) and onnxruntime (MIT). The Android `.so` files use 16 KB-aligned ELF segments and zip alignment (checked with `llvm-readelf` and `zipalign -P 16`). The iOS build uses `SherpaOnnxC.xcframework`.

## Testing

- `flutter test` runs the analyser, filler, word-timing and WAV tests on synthetic signals.
- `example/` is an on-device test app. Build it with `--dart-define=SELFTEST=true` and push WAVs to `/sdcard/Android/data/com.prepsuite.prepsuite_speech_example/files/selftest/`, after the first launch creates that folder. The app transcribes the files, replays `b_answer.wav` through the live pipeline, speaks with Norman, records 3 s from the mic, and logs `PSX …` lines to logcat.

## Limitations

- The app ships about 135 MB of models, and Android keeps a second copy after `ensureReady` because assets inside the APK are not files. On iOS the bundle files are used directly, but this path is untested. Downloading the models on demand would shrink the install.
- Recognition is English-only. Fillers appear only if the model writes them down: Kroko keeps "um", and a quick "uh" may be written "ah" or dropped. Names and jargon may be misheard, so let the user correct the transcript.
- Word end times are estimates (token start plus voicing). Start times come from the model and are usually within about 100 ms.
- iOS has not been built or run here because this Mac has no Xcode. The emulator mic records silence, so live capture was checked by replaying WAV files through the same pipeline.
