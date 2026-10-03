import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/services.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/glass.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/practice_chrome.dart';
import '../../design/robot_stage.dart';
import '../../design/tokens.dart';

/// The widest the reading column gets, so lines stay comfortable in landscape and on tablets.
const double kReadingWidth = 560;

/// The room a step page has: the width of its column, and the height between the top bar and the
/// dock. [docked] is false on a short window, where the dock scrolls with the page instead.
@immutable
class PageRoom {
  const PageRoom({required this.width, required this.height, required this.docked});

  final double width;
  final double height;
  final bool docked;
}

/// Frame for each step of a practice (the job, every question, the notes): a top bar with a close
/// disc and the progress, the page in the middle, and the step's dock at the bottom, on the canvas.
///
/// The dock stays pinned while there is room for it. On a short screen (landscape, an open
/// keyboard, very large text) it becomes the end of the page instead, so nothing is squeezed and
/// every action is still one scroll away. The page's own widgets keep their place either way, so a
/// text field keeps its focus when the keyboard opens.
class CoachScaffold extends StatelessWidget {
  const CoachScaffold({
    super.key,
    required this.onClose,
    required this.progress,
    required this.progressLabel,
    this.children = const [],
    this.builder,
    this.segments = 1,
    this.count,
    this.dock,
    this.controller,
  });

  final VoidCallback onClose;

  /// How far through the practice, 0..1, and what screen readers hear for it ("Question 2 of 3").
  final double progress;
  final String progressLabel;

  /// How many steps the track shows, and where the person is as numbers ("1/3").
  final int segments;
  final String? count;

  /// The page, top to bottom. [builder] builds it instead when the page sizes the coach to the
  /// room it has.
  final List<Widget> children;
  final List<Widget> Function(BuildContext context, PageRoom room)? builder;

  /// The step's actions: a [RecordDock] or a [PillDock].
  final Widget? dock;
  final ScrollController? controller;

  /// Whether the dock can stay pinned in [height] (the space between the status bar and the
  /// keyboard or the bottom of the screen).
  static bool pinsActions(BuildContext context, double height) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return height >= 300 + 140 * scale;
  }

  static const _pageInsets = EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, Space.xxl);

  /// The page's own top and bottom padding, which [PageRoom.height] still includes.
  static double get pagePadding => _pageInsets.vertical;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final dock = this.dock;
    return AmbientBackdrop(
      child: Scaffold(
      backgroundColor: const Color(0x00000000),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final pinned = pinsActions(context, box.maxHeight);
            final hasDock = dock != null;
            Widget docked() => SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: Space.l),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
                    child: Center(
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kReadingWidth), child: dock),
                    ),
                  ),
                );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kReadingWidth + Space.gutter * 2),
                    child: StepTopBar(
                      progress: progress,
                      progressLabel: progressLabel,
                      onClose: onClose,
                      segments: segments,
                      count: count,
                      metalClose: true,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, viewport) {
                      final width = math.min(viewport.maxWidth, kReadingWidth + Space.gutter * 2) - Space.gutter * 2;
                      final room = PageRoom(width: width, height: viewport.maxHeight, docked: pinned && hasDock);
                      final page = builder?.call(context, room) ?? children;
                      return Stack(
                        children: [
                          SingleChildScrollView(
                            controller: controller,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: kReadingWidth + Space.gutter * 2),
                                    child: Padding(
                                      padding: _pageInsets,
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: page),
                                    ),
                                  ),
                                ),
                                Visibility(visible: !pinned && hasDock, child: hasDock ? docked() : const SizedBox.shrink()),
                                Visibility(visible: !hasDock, child: SizedBox(height: bottomInset)),
                              ],
                            ),
                          ),
                          // Words scrolling under the dock fade into the canvas rather than meet an edge.
                          if (pinned && hasDock)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: Space.xxl,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [PrepColors.bg.withValues(alpha: 0), PrepColors.bg],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Visibility(visible: pinned && hasDock, child: hasDock ? docked() : const SizedBox.shrink()),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}

/// How tall [text] sets in [style] across [width], at the person's text size.
double measureText(BuildContext context, String text, TextStyle style, double width, {TextAlign align = TextAlign.center}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: math.max(1, width));
  final height = painter.height;
  painter.dispose();
  return height;
}

/// The coach once there are words to read or edit: still the robot, a step back from the words.
double compactCoachSize(BuildContext context) {
  final media = MediaQuery.of(context);
  final height = media.size.height - media.viewInsets.bottom;
  return height < 600 ? 112 : 140;
}

/// The coach on a question: the hero, about a third of the window high, and smaller only when the
/// words under it ([words], their measured height) need the room, so large text always fits.
double heroCoachSize(BuildContext context, PageRoom room, double words, {double share = 0.34}) {
  final floor = MediaQuery.sizeOf(context).height < 700 ? 96.0 : 120.0;
  if (!room.docked) return compactCoachSize(context);
  final cap = math.max(floor, MediaQuery.sizeOf(context).height * share);
  final fit = room.height - CoachScaffold.pagePadding - words;
  return fit.clamp(floor, cap).toDouble();
}

/// What is left over once the hero coach and its [words] are set, of which a share goes above
/// the coach so the stage sits in the middle of the page rather than under the top bar.
double heroLeadIn(PageRoom room, double words, double size) {
  if (!room.docked) return 0;
  final slack = room.height - CoachScaffold.pagePadding - words - size;
  return slack > 0 ? slack * 0.45 : 0;
}

/// The coach as a lit product on its stage, centred on the page: a dial of hairline ticks around
/// it (an accent arc for real [progress], the questions answered), a satin pedestal and the accent
/// floor light. Its face follows [mood]; [status] (what it is doing) is not printed, so screen
/// readers hear it as a live region on the robot. [side] puts one control beside it (the speaker
/// that reads the feedback), balanced on the other side so the robot stays centred. A new [size]
/// eases in, the screen's one authored moment.
class CoachStage extends StatelessWidget {
  const CoachStage({
    super.key,
    required this.mood,
    required this.status,
    required this.size,
    this.level,
    this.side,
    this.progress,
    this.dial = true,
  });

  final AssistantMood mood;
  final String status;
  final double size;
  final ValueListenable<double>? level;
  final Widget? side;
  final double? progress;
  final bool dial;

  static const double _sideWidth = 56;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final robot = ValueListenableBuilder<AssistantLook>(
      valueListenable: AppScope.of(context).assistant,
      builder: (context, look, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: size),
        duration: still ? Duration.zero : Motion.enter,
        curve: Motion.standard,
        builder: (context, s, _) => Semantics(
          container: true,
          liveRegion: true,
          child: RobotStage(
            look: look,
            robotSize: s,
            mood: mood,
            level: level,
            progress: progress,
            dial: dial,
            semanticLabel: 'Your coach, ${look.name}. $status',
          ),
        ),
      ),
    );
    final side = this.side;
    if (side == null) return Center(child: robot);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: _sideWidth + Space.s),
        robot,
        const SizedBox(width: Space.s),
        SizedBox(width: _sideWidth, child: Center(child: side)),
      ],
    );
  }
}

/// A calm surface for one idea: satin metal, a small icon and a short title, then the words.
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.child, this.title, this.icon, this.iconColor, this.padding, this.hero = false});

  final Widget child;
  final String? title;
  final PrepIcons? icon;
  final Color? iconColor;
  final EdgeInsetsGeometry? padding;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return MetalCard(
      hero: hero,
      radius: hero ? Radii.sheet : Radii.card,
      padding: padding ?? const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Row(
                children: [
                  if (icon != null) ...[
                    PrepIcon(icon!, color: iconColor ?? PrepColors.text2, size: 18),
                    const SizedBox(width: Space.s),
                  ],
                  Expanded(child: Text(title!, style: PrepType.label.copyWith(color: PrepColors.text2))),
                ],
              ),
            ),
            const SizedBox(height: Space.m),
          ],
          child,
        ],
      ),
    );
  }
}

/// A text field set in metal: the field the person types or corrects an answer in. A thin accent
/// line shows focus. [inset] draws it as a raised well instead, for a field inside a card.
class MetalField extends StatefulWidget {
  const MetalField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.hint = '',
    this.minLines = 1,
    this.maxLines = 4,
    this.autofocus = false,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
    this.inset = false,
  });

  final TextEditingController controller;
  final Key? fieldKey;
  final String hint;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool inset;

  @override
  State<MetalField> createState() => _MetalFieldState();
}

class _MetalFieldState extends State<MetalField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus != _focused && mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.inset ? Radii.control : Radii.card;
    final field = TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      textCapitalization: TextCapitalization.sentences,
      style: PrepType.bodyL,
      cursorColor: PrepColors.accent,
      decoration: InputDecoration(
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: widget.hint.isEmpty ? null : widget.hint,
        hintStyle: PrepType.bodyL.copyWith(color: PrepColors.text3),
      ),
    );
    final Widget surface = widget.inset
        ? DecoratedBox(
            decoration: BoxDecoration(color: PrepColors.surface2, borderRadius: BorderRadius.circular(radius)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14), child: field),
          )
        : MetalCard(
            radius: radius,
            padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: 18),
            child: field,
          );
    // A tap anywhere on the surface, not only on the text, puts the caret in the field.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focus.requestFocus,
      excludeFromSemantics: true,
      child: CustomPaint(
        foregroundPainter: _focused ? _FocusLine(radius) : null,
        child: surface,
      ),
    );
  }
}

class _FocusLine extends CustomPainter {
  _FocusLine(this.radius) : _color = PrepColors.accent;

  final double radius;
  final Color _color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _color,
    );
  }

  @override
  bool shouldRepaint(_FocusLine old) => old.radius != radius || old._color != _color;
}

/// The words being recognized while the person speaks: the last of them, quiet, under the
/// question. Only there once words arrive, at the end of the page, so nothing above it moves.
class LiveWords extends StatelessWidget {
  const LiveWords(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: PrepType.bodyL.copyWith(color: PrepColors.text2),
    );
  }
}

/// Time recorded against the limit ("0:12 / 2:00"), from the record button's [progress] (0..1 of
/// [limit]). [big] sets the time as a large numeral over a small limit, for the record dock.
/// Screen readers hear "Recording, 0:12 of 2:00".
class RecordClock extends StatelessWidget {
  const RecordClock({super.key, required this.progress, required this.limit, this.style, this.big = false});

  final ValueListenable<double> progress;
  final Duration limit;
  final TextStyle? style;
  final bool big;

  /// The running time in the dock: a light numeral, set like the big numbers on Home.
  static TextStyle get numeral => PrepType.numeral.copyWith(fontSize: 40, height: 1.1);

  @override
  Widget build(BuildContext context) {
    final max = clock(limit.inMilliseconds);
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, p, _) {
        final now = clock((p.clamp(0.0, 1.0) * limit.inMilliseconds).round());
        const tabular = [FontFeature.tabularFigures()];
        if (big) {
          return Text.rich(
            TextSpan(
              children: [
                TextSpan(text: now, style: numeral),
                TextSpan(
                  text: ' / $max',
                  style: PrepType.label.copyWith(color: PrepColors.text3, fontFeatures: tabular),
                ),
              ],
            ),
            semanticsLabel: 'Recording, $now of $max',
            textAlign: TextAlign.center,
          );
        }
        return Text(
          '$now / $max',
          semanticsLabel: 'Recording, $now of $max',
          style: (style ?? const TextStyle()).copyWith(fontFeatures: tabular),
        );
      },
    );
  }
}

/// Words the person said, set apart as a quote on a slightly raised well (no rule, no colour).
class AnswerQuote extends StatelessWidget {
  const AnswerQuote(this.text, {super.key, this.semanticPrefix = 'You said'});

  final String text;
  final String semanticPrefix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticPrefix: $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PrepColors.surface2,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
          child: Text('“$text”', style: PrepType.quote.copyWith(color: PrepColors.text2)),
        ),
      ),
    );
  }
}

/// Reveals a sentence word by word while the interviewer says it. The full text is laid out from
/// the start (unrevealed words are transparent), so nothing reflows as words appear.
class RevealController extends ValueNotifier<int> {
  RevealController() : super(0);

  String _text = '';
  List<String> _words = const [];
  Timer? _timer;

  String get text => _text;
  List<String> get words => _words;
  bool get complete => value >= _words.length;

  /// Starts revealing [text] at roughly a natural speaking pace. [showAll] snaps to the end
  /// when the voice finishes early (or is interrupted).
  void start(String text, {Duration perWord = const Duration(milliseconds: 330)}) {
    _timer?.cancel();
    _text = text;
    _words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    value = _words.isEmpty ? 0 : 1;
    _timer = Timer.periodic(perWord, (timer) {
      if (value >= _words.length) {
        timer.cancel();
      } else {
        value = value + 1;
      }
    });
  }

  void showAll() {
    _timer?.cancel();
    value = _words.length;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class RevealText extends StatelessWidget {
  const RevealText({super.key, required this.controller, required this.style, this.textAlign = TextAlign.start});

  final RevealController controller;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller,
      builder: (context, shown, _) {
        final words = controller.words;
        final seen = words.take(shown).join(' ');
        final rest = words.skip(shown).join(' ');
        return Semantics(
          label: controller.text,
          header: true,
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: seen),
                if (rest.isNotEmpty)
                  TextSpan(
                    text: '${seen.isEmpty ? '' : ' '}$rest',
                    style: style.copyWith(color: const Color(0x00000000)),
                  ),
              ],
            ),
            textAlign: textAlign,
          ),
        );
      },
    );
  }
}

/// The record control: an accent disc with a microphone, which turns the recording colour with a
/// stop square while it records, inside a 270 degree ring that shows the time. The ring fills
/// during an answer, or empties during a short [countdown] recording.
///
/// [dial] is the practice's large control: a [dialDisc] disc in a ticked dial [dialExtent] across,
/// whose ring and ticks fill with the time used.
class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.recording,
    required this.progress,
    required this.onPressed,
    this.countdown = false,
    this.dimension = 96,
    this.semanticLabel,
    this.dial = false,
  });

  final bool recording;
  final ValueListenable<double> progress;
  final VoidCallback? onPressed;
  final bool countdown;

  /// The square the ring fills; the disc itself is always [disc] across.
  final double dimension;

  /// What screen readers hear; defaults to "Start recording" or "Stop recording".
  final String? semanticLabel;
  final bool dial;

  static const double disc = 76;
  static const double dialDisc = 96;
  static const double dialExtent = 140;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final discSize = dial ? dialDisc : disc;
    final extent = dial ? dialExtent : math.max(dimension, disc + 8);
    final fill = !enabled ? PrepColors.surface2 : (recording ? PrepColors.recording : PrepColors.accent);
    final ink = enabled ? PrepColors.onAccent : PrepColors.text3;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? (recording ? 'Stop recording' : 'Start recording'),
      // excludeSemantics hides the InkWell's own tap, so screen readers need it here.
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: extent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, p, _) {
                  final used = p.clamp(0.0, 1.0);
                  final value = !recording ? 0.0 : (countdown && !dial ? 1 - used : used);
                  return ArcGauge(
                    value: value,
                    size: extent,
                    ticks: dial,
                    stroke: dial ? 3 : 2.5,
                    color: PrepColors.recording,
                    tickColor: recording ? PrepColors.recording : PrepColors.line,
                  );
                },
              ),
            ),
            FocusRing(
              radius: discSize / 2,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: fill),
                duration: still ? Duration.zero : Motion.fade,
                curve: Motion.standard,
                builder: (context, color, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: dial && enabled
                        ? const [BoxShadow(color: Color(0x66000000), offset: Offset(0, 10), blurRadius: 24)]
                        : null,
                  ),
                  child: Material(
                    color: color,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: child,
                  ),
                ),
                child: CustomPaint(
                  foregroundPainter: enabled ? const _DiscRim() : null,
                  child: InkWell(
                    key: const ValueKey('record-button'),
                    onTap: onPressed,
                    customBorder: const CircleBorder(),
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: const Color(0x24000000),
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    child: SizedBox.square(
                      dimension: discSize,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: still ? Duration.zero : Motion.fade,
                          child: recording
                              ? DecoratedBox(
                                  key: const ValueKey('stop'),
                                  decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(6)),
                                  child: SizedBox.square(dimension: discSize * 0.28),
                                )
                              : PrepIcon(PrepIcons.mic, key: const ValueKey('mic'), color: ink, size: discSize * 0.38),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The satin edge on a lit disc: a faint highlight along the top that fades out down the sides.
class _DiscRim extends CustomPainter {
  const _DiscRim();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x47FFFFFF), Color(0x00FFFFFF), Color(0x00000000), Color(0x33000000)],
          stops: const [0, 0.4, 0.6, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_DiscRim old) => false;
}

/// Whether [label] fits in [width] in at most [lines] lines without breaking a word.
bool _labelFits(BuildContext context, String label, TextStyle style, double width, {int lines = 2}) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  double measure(String text) {
    painter.text = TextSpan(text: text, style: style);
    painter.layout();
    return painter.width;
  }

  final words = label.split(' ').map(measure);
  final fits = words.every((w) => w <= width) && measure(label) <= width * lines - (lines > 1 ? Space.l : 0);
  painter.dispose();
  return fits;
}

double _labelWidth(BuildContext context, String label, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The answer dock: the record dial in the middle with one round action on each side (like a
/// camera), and one line underneath: "Tap to answer", or the running time. The sides fade while
/// recording but keep their space, so the dial never moves under a finger. When a side label would
/// not fit beside the dial (very large text, a narrow phone), the sides move under the line as
/// full-width buttons.
class RecordDock extends StatelessWidget {
  const RecordDock({
    super.key,
    required this.button,
    required this.status,
    this.leading,
    this.trailing,
    this.sidesVisible = true,
    this.buttonExtent = RecordButton.dialExtent,
    this.level,
  });

  /// The [RecordButton], [buttonExtent] across.
  final Widget button;
  final double buttonExtent;

  /// The microphone level while recording: a live waveform over the running time.
  final ValueListenable<double>? level;

  /// One line: "Tap to answer", or the [RecordClock] while recording.
  final Widget status;
  final DockAction? leading;
  final DockAction? trailing;
  final bool sidesVisible;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final level = this.level;
    // The line keeps the waveform's and the running time's height, so the dial stays put when
    // recording starts.
    final words = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: LevelBars.height + scaler.scale(RecordClock.numeral.fontSize! * RecordClock.numeral.height!),
      ),
      child: Center(
        child: DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          style: PrepType.label.copyWith(color: PrepColors.text2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [if (level != null) LevelBars(level: level), status],
          ),
        ),
      ),
    );
    final sides = [leading, trailing].nonNulls.toList();
    Widget side(Widget? child) => Visibility(
          visible: sidesVisible && child != null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: child ?? const SizedBox(width: 64, height: 64),
        );
    return LayoutBuilder(
      builder: (context, box) {
        final sideWidth = (box.maxWidth - buttonExtent) / 2 - Space.s;
        final besideButton = sides.every((a) => _labelFits(context, a.label, PrepType.meta, sideWidth));
        if (!besideButton) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: button),
              words,
              for (final action in sides) ...[
                const SizedBox(height: Space.s),
                side(action.asWide()),
              ],
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Center(child: side(leading))),
                button,
                Expanded(child: Center(child: side(trailing))),
              ],
            ),
            words,
          ],
        );
      },
    );
  }
}

/// The live microphone level as a short waveform: the last moments of the voice as thin bars in
/// the recording colour, newest on the right. Decorative for screen readers (the clock says it).
class LevelBars extends StatefulWidget {
  const LevelBars({super.key, required this.level});

  final ValueListenable<double> level;

  static const double height = 28;

  @override
  State<LevelBars> createState() => _LevelBarsState();
}

class _LevelBarsState extends State<LevelBars> {
  static const _count = 32;
  final _bars = List<double>.filled(_count, 0, growable: true);

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(LevelBars old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      old.level.removeListener(_onLevel);
      widget.level.addListener(_onLevel);
    }
  }

  @override
  void dispose() {
    widget.level.removeListener(_onLevel);
    super.dispose();
  }

  void _onLevel() {
    if (!mounted) return;
    setState(() {
      _bars.removeAt(0);
      _bars.add(widget.level.value.clamp(0.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: _count * 6.0,
        height: LevelBars.height,
        child: CustomPaint(painter: _BarsPainter(List.of(_bars), PrepColors.recording)),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.bars, this.color);

  final List<double> bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / bars.length;
    final mid = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;
    for (final (i, v) in bars.indexed) {
      // Older bars fade a little, so the newest sound reads as the leading edge.
      final age = (i + 1) / bars.length;
      final half = math.max(1.5, v * (size.height / 2 - 2));
      final x = step * (i + 0.5);
      paint.color = color.withValues(alpha: 0.35 + 0.65 * age);
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => !listEquals(old.bars, bars) || old.color != color;
}

/// The dock for every other step: the one primary pill, with a round action on one or both sides
/// ([leading], [trailing]). Two sides keep the pill centred, the way the answer dock centres the
/// dial. When the sides' labels would squeeze the pill (very large text, a narrow phone), the pill
/// takes the full width and the sides sit under it as full-width buttons.
class PillDock extends StatelessWidget {
  const PillDock({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.leading,
    this.trailing,
    this.trailingVisible = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final PrepIcons? icon;
  final bool busy;
  final DockAction? leading;
  final DockAction? trailing;

  /// False hides [trailing] but keeps its place (the coach panel is already open).
  final bool trailingVisible;

  @override
  Widget build(BuildContext context) {
    final pill = PrimaryButton(label, onPressed: onPressed, icon: icon, busy: busy);
    final leading = this.leading;
    final trailing = this.trailing;
    if (leading == null && trailing == null) return pill;
    return LayoutBuilder(
      builder: (context, box) {
        final sides = [leading, trailing].nonNulls;
        final sideWidth = sides
            .map((a) => _labelWidth(context, a.label, PrepType.meta) + Space.s)
            .fold<double>(DockAction.compactWidth, math.max);
        final count = sides.length;
        final pillNeeds = _labelWidth(context, label, PrepType.button) + Space.xl * 2 + (busy || icon != null ? 26 : 0);
        final fits = box.maxWidth - count * (sideWidth + Space.m) >= pillNeeds;
        Widget hideable(Widget child) => Visibility(
              visible: trailingVisible,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: child,
            );
        if (fits) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[SizedBox(width: sideWidth, child: leading), const SizedBox(width: Space.m)],
              Expanded(child: pill),
              if (trailing != null) ...[
                const SizedBox(width: Space.m),
                SizedBox(width: sideWidth, child: hideable(trailing)),
              ],
            ],
          );
        }
        final wides = [leading?.asWide(), if (trailing != null && trailingVisible) trailing.asWide()].nonNulls.toList();
        final paired = wides.length == 2 &&
            wides.every(
              (a) => _labelWidth(context, a.label, PrepType.label) + 20 + Space.s + Space.l * 2 <= (box.maxWidth - Space.s) / 2,
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pill,
            const SizedBox(height: Space.s),
            if (paired)
              Row(
                children: [
                  Expanded(child: wides[0]),
                  const SizedBox(width: Space.s),
                  Expanded(child: wides[1]),
                ],
              )
            else
              for (final (i, wide) in wides.indexed) ...[
                if (i > 0) const SizedBox(height: Space.s),
                wide,
              ],
          ],
        );
      },
    );
  }
}

/// A secondary action in a dock: a round metal disc with a one or two word label under it, all of
/// it one target. [wide] lays it out as a full-width metal pill instead. Pressing settles the disc
/// and darkens it.
class DockAction extends StatefulWidget {
  const DockAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.wide = false,
  });

  final PrepIcons icon;
  final String label;
  final VoidCallback? onPressed;

  /// What screen readers hear, when the short [label] needs more words ("Hear the question again").
  final String? semanticLabel;
  final bool wide;

  /// The narrowest a disc and its label take.
  static const double compactWidth = 64;
  static const double _disc = 52;

  DockAction asWide() =>
      DockAction(icon: icon, label: label, semanticLabel: semanticLabel, onPressed: onPressed, wide: true);

  @override
  State<DockAction> createState() => _DockActionState();
}

class _DockActionState extends State<DockAction> {
  bool _pressed = false;

  @override
  void didUpdateWidget(DockAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tint = enabled ? PrepColors.text : PrepColors.text3;
    final metal = _pressed ? Color.lerp(PrepColors.surface2, const Color(0xFF000000), 0.25)! : PrepColors.surface2;
    final Widget body;
    final double radius;
    if (widget.wide) {
      radius = 24;
      body = DecoratedBox(
        decoration: ShapeDecoration(color: metal, shape: StadiumBorder(side: BorderSide(color: PrepColors.rimLight))),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PrepIcon(widget.icon, color: tint, size: 20),
                const SizedBox(width: Space.s),
                Flexible(
                  child: Text(widget.label, textAlign: TextAlign.center, style: PrepType.label.copyWith(color: tint)),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      radius = Radii.control;
      body = ConstrainedBox(
        constraints: const BoxConstraints(minWidth: DockAction.compactWidth, minHeight: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // As tall as the pill beside it, so the disc and the pill share a centre line.
            SizedBox(
              height: 56,
              child: Center(
                child: AnimatedScale(
                  scale: _pressed && !still ? 0.96 : 1,
                  duration: Motion.press,
                  curve: Motion.standard,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: metal,
                      shape: CircleBorder(side: BorderSide(color: PrepColors.rimLight)),
                    ),
                    child: SizedBox.square(
                      dimension: DockAction._disc,
                      child: Center(child: PrepIcon(widget.icon, color: tint, size: 22)),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: PrepType.meta.copyWith(color: enabled ? PrepColors.text2 : PrepColors.text3),
            ),
            const SizedBox(height: Space.xs),
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusRing(
        radius: radius,
        child: Material(
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (down) {
              if (down != _pressed) setState(() => _pressed = down && enabled);
            },
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// An honest progress line: says what is happening, with a thin indeterminate bar.
class LoadingLine extends StatelessWidget {
  const LoadingLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: PrepType.bodyLMedium),
          const SizedBox(height: Space.m),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(minHeight: 2, color: PrepColors.accent, backgroundColor: PrepColors.line),
          ),
        ],
      ),
    );
  }
}

/// A problem, said plainly, with what to do about it. [centered] sets it under a centred question.
class ProblemNote extends StatelessWidget {
  const ProblemNote({super.key, required this.title, required this.body, this.centered = false});

  final String title;
  final String body;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.start;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(title, style: PrepType.titleM, textAlign: align),
          const SizedBox(height: Space.xs),
          Text(body, style: PrepType.body, textAlign: align),
        ],
      ),
    );
  }
}

String clock(int ms) {
  final total = (ms / 1000).floor().clamp(0, 5999);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

