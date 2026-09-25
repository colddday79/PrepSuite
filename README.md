# PrepSuite

Interview practice for a first job, built in Flutter for Android and iPhone: say the job, answer
questions out loud, get short honest feedback on each answer, and finish with last-minute notes.

## Run

    cd ~/Documents/PrepSuite
    tools/coach/run-local.sh &                    # the AI coach server (mock mode until a key is added)
    flutter run                                   # the app (emulator or a plugged-in phone)
    flutter run --dart-define=COACH_FAKE=true     # built-in sample coach, no server needed
    flutter run --dart-define=COACH_URL=http://<your-mac-ip>:8787/coach   # a real phone: see below

The coach server defaults to `http://10.0.2.2:8787/coach` on the Android emulator and
`http://localhost:8787/coach` on the iOS simulator. Plain http is allowed only in debug builds.
Before the first run in a new clone, create the speech models with `tools/voice/fetch_models.sh`.
Add a Claude key as described in `tools/coach/README.md`.

## Run on your phone (Android)

1. On the phone: Settings → About phone → tap **Build number** seven times, then
   Settings → System → Developer options → turn on **USB debugging**. Plug it into the Mac and
   tap **Allow** on the "Allow USB debugging?" prompt.
2. Put the phone on the same Wi-Fi as the Mac. Start the coach on the Mac. It listens on
   `0.0.0.0:8787`, so the phone can reach it:

       cd ~/Documents/PrepSuite
       tools/voice/fetch_models.sh            # once per clone: the offline speech models (~135 MB)
       tools/coach/run-local.sh &

3. Find the Mac's Wi-Fi address and the phone's device id:

       ipconfig getifaddr en0                 # e.g. 192.168.45.212 (this Mac, 25 Sep 2026)
       flutter devices                        # copy the phone's id from the second column

4. Run the app on the phone (a debug build; it can use plain http to the Mac):

       flutter run -d <phone-id> --dart-define=COACH_URL=http://192.168.45.212:8787/coach

   Check the connection first with `http://192.168.45.212:8787/health` in the phone's browser; it
   should show `{"ok":true,...}`. If it doesn't load, make sure the macOS firewall lets Deno accept
   incoming connections. The first launch copies the speech files onto the phone, which takes a few
   seconds. Allow the microphone when asked.

Speech options (`--dart-define`): `SPEECH_FAKE=true` uses canned demo speech instead of the
microphone. `INTERVIEWER_VOICE=none` turns off read-aloud. In debug builds only,
`SPEECH_TEST_WAVS=/data/local/tmp/job.wav,/data/local/tmp/a1.wav` replays those WAV files as the
next recordings, through the real recogniser. The emulator's microphone records silence, so this is
how to test voice there; after the last file the real microphone is used again. A build without the
speech models (a fresh clone, or CI) still builds and runs: the app says voice isn't available and
offers typing.

## Layout

- `lib/`, `android/`, `ios/`, `test/`: the Flutter app
- `packages/prepsuite_speech/`: offline speech-to-text, delivery metrics and the Norman interviewer voice (models: `tools/voice/fetch_models.sh`)
- `supabase/functions/coach/`: the Claude coach service (Deno)
- `tools/blender/`: scripts that render the gold assistant
- `docs/`: PRD, build plan and handoff notes
- `legacy/android-native/`: the earlier Kotlin/Compose app, kept for reference

## Check

    flutter analyze
    flutter test

Mona Sans is licensed under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
