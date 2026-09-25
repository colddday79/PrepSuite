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
    unawaited(widget.services.profile.restore());
  }

  @override
  void didUpdateWidget(PrepSuiteApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.services.sessions != oldWidget.services.sessions) {
      unawaited(widget.services.sessions.restore());
    }
    if (widget.services.profile != oldWidget.services.profile) {
      unawaited(widget.services.profile.restore());
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

/// Dark only. Mona Sans everywhere (every Material text role maps to a [PrepType] style, so no
/// default leaks through at the variable font's thin default weight), gold as the one accent, a
/// quiet press tint instead of ripples, and no hover effects. Dialogs, the date picker, sheets,
/// snack bars and selection controls are drawn from the same palette as the custom components.
ThemeData prepTheme() {
  const clear = Color(0x00000000);
  const radius = BorderRadius.all(Radius.circular(Radii.control));
  const controlShape = RoundedRectangleBorder(borderRadius: radius);

  // State tints: pressed and focused only. Hover never changes anything.
  WidgetStateProperty<Color?> tint(Color base, {double pressed = 0.14, double focused = 0.2}) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return base.withValues(alpha: pressed);
        if (states.contains(WidgetState.focused)) return base.withValues(alpha: focused);
        return null;
      });

  // Selected is gold; inactive controls (WCAG-exempt) fade; everything else uses [rest].
  WidgetStateProperty<Color?> selectable({required Color selected, required Color rest}) =>
      WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) return (on ? selected : rest).withValues(alpha: 0.38);
        return on ? selected : rest;
      });

  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color, width: width));

  final input = InputDecorationThemeData(
    filled: true,
    fillColor: PrepColors.surface1,
    hintStyle: PrepType.bodyL.copyWith(color: PrepColors.text3),
    labelStyle: PrepType.bodyL.copyWith(color: PrepColors.text2),
    floatingLabelStyle: PrepType.label.copyWith(color: PrepColors.accent),
    helperStyle: PrepType.meta,
    errorStyle: PrepType.meta.copyWith(color: PrepColors.danger),
    errorMaxLines: 3,
    iconColor: PrepColors.text2,
    prefixIconColor: PrepColors.text2,
    suffixIconColor: PrepColors.text2,
    contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
    border: outline(PrepColors.lineStrong),
    enabledBorder: outline(PrepColors.lineStrong),
    focusedBorder: outline(PrepColors.accent, 1.5),
    disabledBorder: outline(PrepColors.line),
    errorBorder: outline(PrepColors.danger),
    focusedErrorBorder: outline(PrepColors.danger, 1.5),
  );

  ButtonStyle textAction(Color color) => TextButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: PrepColors.text3,
        textStyle: PrepType.label,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        shape: controlShape,
        splashFactory: NoSplash.splashFactory,
      ).copyWith(overlayColor: tint(PrepColors.press));

  // Day and year cells: gold fill when selected, a gold tint under keyboard focus.
  final cellOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    final on = states.contains(WidgetState.selected);
    if (states.contains(WidgetState.pressed)) return (on ? PrepColors.bg : PrepColors.text).withValues(alpha: 0.12);
    if (states.contains(WidgetState.focused)) return on ? PrepColors.bg.withValues(alpha: 0.2) : PrepColors.accent.withValues(alpha: 0.28);
    return null;
  });
  final cellFill = WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? PrepColors.accent : null);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'MonaSans',
    scaffoldBackgroundColor: PrepColors.bg,
    canvasColor: PrepColors.bg,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: PrepColors.accent,
      onPrimary: PrepColors.bg,
      primaryContainer: PrepColors.accentTint,
      onPrimaryContainer: PrepColors.text,
      secondary: PrepColors.accent,
      onSecondary: PrepColors.bg,
      secondaryContainer: PrepColors.accentTint,
      onSecondaryContainer: PrepColors.text,
      tertiary: PrepColors.text2,
      onTertiary: PrepColors.bg,
      error: PrepColors.danger,
      onError: PrepColors.bg,
      surface: PrepColors.bg,
      onSurface: PrepColors.text,
      onSurfaceVariant: PrepColors.text2,
      surfaceDim: PrepColors.bg,
      surfaceBright: PrepColors.surface2,
      surfaceContainerLowest: PrepColors.bg,
      surfaceContainerLow: PrepColors.surface1,
      surfaceContainer: PrepColors.surface1,
      surfaceContainerHigh: PrepColors.surface2,
      surfaceContainerHighest: PrepColors.surface2,
      // Control outlines that are the only boundary need 3:1, so outline is text3, not a hairline.
      outline: PrepColors.text3,
      outlineVariant: PrepColors.line,
      inverseSurface: PrepColors.text,
      onInverseSurface: PrepColors.bg,
      inversePrimary: PrepColors.accentTint,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      surfaceTint: clear,
    ),
    textTheme: TextTheme(
      displayLarge: PrepType.display,
      displayMedium: PrepType.display,
      displaySmall: PrepType.headline,
      headlineLarge: PrepType.headline,
      headlineMedium: PrepType.headline,
      headlineSmall: PrepType.titleL,
      titleLarge: PrepType.titleL,
      titleMedium: PrepType.titleM,
      titleSmall: PrepType.label,
      bodyLarge: PrepType.bodyL,
      bodyMedium: PrepType.body,
      bodySmall: PrepType.meta,
      labelLarge: PrepType.label,
      labelMedium: PrepType.meta,
      labelSmall: PrepType.caption,
    ),
    iconTheme: const IconThemeData(color: PrepColors.text2, size: 24),
    splashFactory: NoSplash.splashFactory,
    highlightColor: PrepColors.press.withValues(alpha: 0.14),
    // Material widgets without a FocusRing (date cells, stray InkWells) still show keyboard focus.
    focusColor: PrepColors.accent.withValues(alpha: 0.2),
    hoverColor: clear,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    dividerTheme: const DividerThemeData(color: PrepColors.line, thickness: 1, space: 1),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: PrepColors.accent,
      selectionColor: PrepColors.accent.withValues(alpha: 0.35),
      selectionHandleColor: PrepColors.accent,
    ),
    inputDecorationTheme: input,
    appBarTheme: AppBarTheme(
      backgroundColor: PrepColors.bg,
      foregroundColor: PrepColors.text,
      surfaceTintColor: clear,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: PrepType.titleM,
    ),
    textButtonTheme: TextButtonThemeData(style: textAction(PrepColors.accent)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PrepColors.text,
        foregroundColor: PrepColors.bg,
        disabledBackgroundColor: PrepColors.surface2,
        disabledForegroundColor: PrepColors.text3,
        textStyle: PrepType.button,
        minimumSize: const Size(64, 56),
        shape: controlShape,
        elevation: 0,
        splashFactory: NoSplash.splashFactory,
      ).copyWith(overlayColor: tint(PrepColors.bg, pressed: 0.1, focused: 0.12)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PrepColors.text,
        disabledForegroundColor: PrepColors.text3,
        side: const BorderSide(color: PrepColors.lineStrong),
        textStyle: PrepType.label,
        minimumSize: const Size(48, 48),
        shape: controlShape,
        splashFactory: NoSplash.splashFactory,
      ).copyWith(overlayColor: tint(PrepColors.press)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: PrepColors.text2,
        minimumSize: const Size(48, 48),
        splashFactory: NoSplash.splashFactory,
      ).copyWith(overlayColor: tint(PrepColors.press)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PrepColors.surface2,
      surfaceTintColor: clear,
      shadowColor: clear,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.sheet))),
      titleTextStyle: PrepType.titleL,
      contentTextStyle: PrepType.body,
      iconColor: PrepColors.text2,
      // QuietButton pads its label by 12, so its text lines up with the 24 dp content edge.
      actionsPadding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
      insetPadding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xxl),
      barrierColor: PrepColors.scrim,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: PrepColors.surface2,
      surfaceTintColor: clear,
      shadowColor: clear,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.sheet))),
      headerBackgroundColor: clear,
      headerForegroundColor: PrepColors.text,
      headerHeadlineStyle: PrepType.headline,
      headerHelpStyle: PrepType.label,
      subHeaderForegroundColor: PrepColors.text2,
      toggleButtonTextStyle: PrepType.label,
      weekdayStyle: PrepType.meta.copyWith(color: PrepColors.text3),
      dayStyle: PrepType.bodyL,
      dayForegroundColor: selectable(selected: PrepColors.bg, rest: PrepColors.text),
      dayBackgroundColor: cellFill,
      dayOverlayColor: cellOverlay,
      todayForegroundColor: selectable(selected: PrepColors.bg, rest: PrepColors.accent),
      todayBackgroundColor: cellFill,
      todayBorder: const BorderSide(color: PrepColors.accent),
      yearStyle: PrepType.bodyL,
      yearForegroundColor: selectable(selected: PrepColors.bg, rest: PrepColors.text2),
      yearBackgroundColor: cellFill,
      yearOverlayColor: cellOverlay,
      rangePickerBackgroundColor: PrepColors.bg,
      rangePickerSurfaceTintColor: clear,
      rangePickerHeaderBackgroundColor: PrepColors.bg,
      rangePickerHeaderForegroundColor: PrepColors.text,
      rangePickerHeaderHeadlineStyle: PrepType.titleL,
      rangePickerHeaderHelpStyle: PrepType.label,
      rangeSelectionBackgroundColor: PrepColors.accentTint,
      dividerColor: PrepColors.line,
      inputDecorationTheme: input,
      // One main action: Cancel is quiet, the confirm action carries the gold.
      cancelButtonStyle: textAction(PrepColors.text2),
      confirmButtonStyle: textAction(PrepColors.accent),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PrepColors.surface1,
      modalBackgroundColor: PrepColors.surface1,
      surfaceTintColor: clear,
      shadowColor: clear,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: PrepColors.scrim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
      dragHandleColor: PrepColors.lineStrong,
      dragHandleSize: Size(32, 4),
      clipBehavior: Clip.antiAlias,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PrepColors.surface2,
      contentTextStyle: PrepType.body.copyWith(color: PrepColors.text),
      actionTextColor: PrepColors.accent,
      disabledActionTextColor: PrepColors.text3,
      closeIconColor: PrepColors.text2,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: PrepColors.lineStrong)),
      insetPadding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: selectable(selected: PrepColors.bg, rest: PrepColors.text3),
      trackColor: selectable(selected: PrepColors.accent, rest: PrepColors.surface2),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? clear : PrepColors.text3.withValues(alpha: states.contains(WidgetState.disabled) ? 0.38 : 1),
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1.5),
      overlayColor: tint(PrepColors.accent, pressed: 0.12, focused: 0.24),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    radioTheme: RadioThemeData(
      fillColor: selectable(selected: PrepColors.accent, rest: PrepColors.text3),
      overlayColor: tint(PrepColors.accent, pressed: 0.12, focused: 0.24),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return clear;
        return PrepColors.accent.withValues(alpha: states.contains(WidgetState.disabled) ? 0.38 : 1);
      }),
      checkColor: const WidgetStatePropertyAll(PrepColors.bg),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return const BorderSide(color: clear, width: 0);
        return BorderSide(color: PrepColors.text3.withValues(alpha: states.contains(WidgetState.disabled) ? 0.38 : 1), width: 1.5);
      }),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
      overlayColor: tint(PrepColors.accent, pressed: 0.12, focused: 0.24),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Space.gutter),
      minVerticalPadding: Space.m,
      iconColor: PrepColors.text2,
      textColor: PrepColors.text,
      selectedColor: PrepColors.text,
      tileColor: clear,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: PrepColors.surface2,
      surfaceTintColor: clear,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: PrepColors.lineStrong)),
      textStyle: PrepType.bodyL,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: PrepColors.surface2,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border.all(color: PrepColors.lineStrong),
      ),
      textStyle: PrepType.meta.copyWith(color: PrepColors.text),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(PrepColors.text3.withValues(alpha: 0.6)),
      thickness: const WidgetStatePropertyAll(3),
      radius: const Radius.circular(2),
      crossAxisMargin: 2,
      mainAxisMargin: Space.xs,
      minThumbLength: 40,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PrepColors.accent,
      linearTrackColor: PrepColors.line,
      circularTrackColor: PrepColors.line,
    ),
  );
}
