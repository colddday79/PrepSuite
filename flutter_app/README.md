# PrepSuite (Flutter)

Interview practice for a first job: say the job, answer questions out loud, get short honest
feedback on each answer, and finish with last-minute notes. One codebase for Android and iPhone.

## Run

    flutter run                                   # talks to the coach server on this computer
    flutter run --dart-define=COACH_FAKE=true     # built-in sample coach, no server needed
    flutter run --dart-define=COACH_URL=http://192.168.1.20:8787/coach   # coach on another machine

The coach server defaults to `http://10.0.2.2:8787/coach` on the Android emulator and
`http://localhost:8787/coach` on the iOS simulator. Plain http is allowed only in debug builds
(Android `src/debug` network security config, iOS `Info-Debug.plist`).

Speech is still the demo stand-in (`FakeSpeechCapture` / `FakeInterviewerVoice`); swap in
`packages/prepsuite_speech` in `createServices()` in `lib/main.dart`.

## Check

    flutter analyze
    flutter test

Mona Sans is licensed under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
