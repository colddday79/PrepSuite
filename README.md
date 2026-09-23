# PrepSuite

Android-first interview practice. The app is currently a working skeleton: design system, navigation, onboarding, the voice practice screen (live AGSL orb, text-to-speech, local WAV recording with silence detection), quiet practice exercises, history with filters, and settings. Transcription, feedback, sign-in and billing are not connected yet.

## Build

Gradle needs Android Studio's bundled JDK 21 (the system Java 8 will not work):

    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    ./gradlew testDebugUnitTest assembleDebug
    adb install -r app/build/outputs/apk/debug/app-debug.apk

Toolchain: AGP 9.2.1, Gradle 9.4.1, Kotlin 2.4.0, Compose BOM 2026.06.01, compileSdk 36, minSdk 29.

## Services

- GitHub: https://github.com/jungwooshim1212/PrepSuite
- Supabase project reference: `qtwhzseowgktmocsjwib` (dev project; no migrations or client connection yet)

Keep credentials in local secret storage or server-side environment configuration, never in Git. No old SportsSnap application source is included.
