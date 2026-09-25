import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../features/home/home_screen.dart';
import 'services.dart';

class PrepSuiteApp extends StatefulWidget {
  const PrepSuiteApp({super.key, required this.services});

  final AppServices services;

  @override
  State<PrepSuiteApp> createState() => _PrepSuiteAppState();
}

class _PrepSuiteAppState extends State<PrepSuiteApp> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.services.sessions.restore());
  }

  @override
  void didUpdateWidget(PrepSuiteApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.services.sessions != oldWidget.services.sessions) {
      unawaited(widget.services.sessions.restore());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        child: MaterialApp(
          title: 'PrepSuite',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: prepTheme(),
          theme: prepTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

/// Dark only. Mona Sans everywhere, gold as the one accent, a quiet press tint instead of ripples,
/// and no hover effects.
ThemeData prepTheme() {
  final press = PrepColors.press;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'MonaSans',
    scaffoldBackgroundColor: PrepColors.bg,
    canvasColor: PrepColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: PrepColors.accent,
      onPrimary: PrepColors.bg,
      secondary: PrepColors.accent,
      onSecondary: PrepColors.bg,
      surface: PrepColors.bg,
      onSurface: PrepColors.text,
      surfaceContainerHighest: PrepColors.surface2,
      onSurfaceVariant: PrepColors.text2,
      outline: PrepColors.lineStrong,
      outlineVariant: PrepColors.line,
      error: PrepColors.danger,
      onError: PrepColors.bg,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: press.withValues(alpha: 0.12),
    focusColor: press.withValues(alpha: 0.08),
    hoverColor: const Color(0x00000000),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: PrepColors.accent,
      selectionColor: PrepColors.accent.withValues(alpha: 0.35),
      selectionHandleColor: PrepColors.accent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: PrepColors.surface2,
      surfaceTintColor: Color(0x00000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.sheet))),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PrepColors.surface1,
      modalBackgroundColor: PrepColors.surface1,
      surfaceTintColor: Color(0x00000000),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: PrepColors.accent, linearTrackColor: PrepColors.line),
  );
}
