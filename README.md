# PrepSuite

Interview practice for a first job, built in Flutter for Android and iPhone: say the job, answer
questions out loud, get short honest feedback on each answer, and finish with last-minute notes.

## Run

    cd ~/Documents/PrepSuite
    tools/coach/run-local.sh &                    # the AI coach server (mock mode until a key is added)
    flutter run                                   # the app (emulator or a plugged-in phone)
    flutter run --dart-define=COACH_FAKE=true     # built-in sample coach, no server needed
    flutter run --dart-define=COACH_URL=http://<your-mac-ip>:8787/coach   # a real phone on the same Wi-Fi

The coach server defaults to `http://10.0.2.2:8787/coach` on the Android emulator and
`http://localhost:8787/coach` on the iOS simulator. Plain http is allowed only in debug builds.
Add a Claude key as described in `tools/coach/README.md`.

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
