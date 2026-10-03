import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/services.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/practice_chrome.dart';
import '../../design/tokens.dart';

/// The widest the reading column gets, so lines stay comfortable in landscape and on tablets.
const double kReadingWidth = 560;

/// Frame for each step of a practice (the job, every question, the notes): a top bar with close
/// and progress, the page in the middle, and the step's actions in a bar at the bottom.
///
/// The bar stays pinned while there is room for it. On a short screen (landscape, an open
/// keyboard, very large text) it becomes the end of the page instead, so nothing is squeezed and
/// every action is still one scroll away. The page's own widgets keep their place either way, so a
/// text field keeps its focus when the keyboard opens.
class CoachScaffold extends StatelessWidget {
  const CoachScaffold({
    super.key,
    required this.onClose,
    required this.progress,
    required this.progressLabel,
    required this.children,
    this.caption,
    this.actions = const [],
    this.controller,
  });

  final VoidCallback onClose;

  /// How far through the practice, 0..1, and what screen readers hear for it ("Question 2 of 3").
  final double progress;
  final String progressLabel;

  /// A short line under the progress ("Question 2 of 3 · Barista").
  final String? caption;

  /// The page, top to bottom.
  final List<Widget> children;

  /// The bottom bar: one [PrimaryButton] and at most two quiet actions, or the answer controls.
  final List<Widget> actions;
  final ScrollController? controller;

  /// Whether the action bar can stay pinned in [height] (the space between the status bar and
  /// the keyboard or the bottom of the screen).
  static bool pinsActions(BuildContext context, double height) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return height >= 300 + 140 * scale;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final pinned = pinsActions(context, box.maxHeight);
            final hasBar = actions.isNotEmpty;
            Widget bar() => BottomActionBar(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: kReadingWidth),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: actions),
                      ),
                    ),
                  ],
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
                      caption: pinned ? caption : null,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: controller,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Visibility(
                          visible: !pinned && caption != null,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: kReadingWidth + Space.gutter * 2),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, 0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Text(caption ?? '', style: PrepType.meta),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: kReadingWidth + Space.gutter * 2),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.x3),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                            ),
                          ),
                        ),
                        Visibility(visible: !pinned && hasBar, child: hasBar ? bar() : const SizedBox.shrink()),
                        Visibility(visible: !hasBar, child: SizedBox(height: bottomInset)),
                      ],
                    ),
                  ),
                ),
                Visibility(visible: pinned && hasBar, child: hasBar ? bar() : const SizedBox.shrink()),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// How big the coach is beside the words: present but never in the way.
double coachSize(BuildContext context) {
  final media = MediaQuery.of(context);
  final height = media.size.height - media.viewInsets.bottom;
  if (height >= 760) return 88;
  if (height >= 600) return 72;
  return 56;
}

/// The coach: a small robot whose face follows [mood], and its name. What it is doing ([status])
/// is not printed (the controls under the page already say it); screen readers hear it as a live
/// region, so the robot never carries the meaning alone.
class CoachLine extends StatelessWidget {
  const CoachLine({super.key, required this.mood, required this.status, this.level, this.size});

  final AssistantMood mood;
  final String status;
  final ValueListenable<double>? level;

  /// Defaults to [coachSize].
  final double? size;

  @override
  Widget build(BuildContext context) {
    final side = size ?? coachSize(context);
    return ValueListenableBuilder<AssistantLook>(
      valueListenable: AppScope.of(context).assistant,
      builder: (context, look, _) => Row(
        children: [
          // The avatar stands the white robot on its own pale disc in the coach's colour.
          SizedBox.square(
            dimension: side,
            child: AssistantAvatar(
              look: look,
              size: side,
              mood: mood,
              level: level,
              hud: false,
              semanticLabel: 'Your coach, ${look.name}',
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            // The avatar already says the name, so this node carries only the state.
            child: Semantics(
              container: true,
              liveRegion: true,
              label: status,
              excludeSemantics: true,
              child: Text(look.name, style: PrepType.titleM),
            ),
          ),
        ],
      ),
    );
  }
}

/// A calm surface for one idea: surface fill, a hairline border, an icon and a short title.
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.child, this.title, this.icon, this.iconColor, this.padding});

  final Widget child;
  final String? title;
  final PrepIcons? icon;
  final Color? iconColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PrepColors.surface1,
        border: Border.all(color: PrepColors.line),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(
                header: true,
                child: Row(
                  children: [
                    if (icon != null) ...[PrepIcon(icon!, color: iconColor ?? PrepColors.text2, size: 20), const SizedBox(width: Space.s)],
                    Expanded(child: Text(title!, style: PrepType.label.copyWith(color: PrepColors.text))),
                  ],
                ),
              ),
              const SizedBox(height: Space.m),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Where a spoken answer appears: the words as they are recognized while recording, and the last
/// of them while they are turned into text. It sits at the end of the page and only appears once
/// there are words, so nothing above it moves.
class TranscriptCard extends StatelessWidget {
  const TranscriptCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 112),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PrepColors.surface1,
          border: Border.all(color: PrepColors.line),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(text, style: PrepType.bodyL.copyWith(color: PrepColors.text2)),
        ),
      ),
    );
  }
}

/// Time recorded against the limit ("0:12 / 2:00"), from the record button's [progress] (0..1 of
/// [limit]). Screen readers hear "Recording, 0:12 of 2:00".
class RecordClock extends StatelessWidget {
  const RecordClock({super.key, required this.progress, required this.limit, this.style});

  final ValueListenable<double> progress;
  final Duration limit;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final max = clock(limit.inMilliseconds);
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, p, _) {
        final now = clock((p.clamp(0.0, 1.0) * limit.inMilliseconds).round());
        return Text(
          '$now / $max',
          semanticsLabel: 'Recording, $now of $max',
          style: (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        );
      },
    );
  }
}

/// Words the person said, set apart as a quote: a rule on the left and the quote type.
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
        decoration: BoxDecoration(border: Border(left: BorderSide(color: PrepColors.lineStrong, width: 2))),
        child: Padding(
          padding: const EdgeInsets.only(left: Space.m, top: Space.xxs, bottom: Space.xxs),
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
  const RevealText({super.key, required this.controller, required this.style});

  final RevealController controller;
  final TextStyle style;

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
          ),
        );
      },
    );
  }
}

/// The record control: a solid ink disc with a microphone, which turns the recording color with a
/// stop square while it records. A thin ring around it shows time: it
/// fills during an answer, or empties during a short countdown recording.
class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.recording,
    required this.progress,
    required this.onPressed,
    this.countdown = false,
    this.dimension = 96,
    this.semanticLabel,
  });

  final bool recording;
  final ValueListenable<double> progress;
  final VoidCallback? onPressed;
  final bool countdown;

  /// The square the ring fills; the disc itself is always [disc] across.
  final double dimension;

  /// What screen readers hear; defaults to "Start recording" or "Stop recording".
  final String? semanticLabel;

  static const double disc = 76;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fill = !enabled ? PrepColors.surface2 : (recording ? PrepColors.recording : PrepColors.ink);
    final ink = enabled ? PrepColors.bg : PrepColors.text3;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? (recording ? 'Stop recording' : 'Start recording'),
      // excludeSemantics hides the InkWell's own tap, so screen readers need it here.
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: math.max(dimension, disc + 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, p, _) => CustomPaint(
                  painter: _TimeRing(progress: p, countdown: countdown, active: recording),
                ),
              ),
            ),
            FocusRing(
              radius: disc / 2,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: fill),
                duration: still ? Duration.zero : Motion.fade,
                curve: Motion.standard,
                builder: (context, color, child) => Material(
                  color: color,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
                child: InkWell(
                  key: const ValueKey('record-button'),
                  onTap: onPressed,
                  customBorder: const CircleBorder(),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: PrepColors.bg.withValues(alpha: 0.18),
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  child: SizedBox.square(
                    dimension: disc,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: still ? Duration.zero : Motion.fade,
                        child: recording
                            ? DecoratedBox(
                                key: const ValueKey('stop'),
                                decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(5)),
                                child: const SizedBox.square(dimension: 24),
                              )
                            : PrepIcon(PrepIcons.mic, key: const ValueKey('mic'), color: ink, size: 32),
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

class _TimeRing extends CustomPainter {
  _TimeRing({required this.progress, required this.countdown, required this.active});

  final double progress;
  final bool countdown;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = PrepColors.line,
    );
    if (!active) return;
    final p = progress.clamp(0.0, 1.0);
    final sweep = (countdown ? 1 - p : p) * 2 * math.pi;
    if (sweep <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = PrepColors.recording,
    );
  }

  @override
  bool shouldRepaint(_TimeRing old) => old.progress != progress || old.countdown != countdown || old.active != active;
}

/// The answer controls in the bottom bar: the record button in the middle with one secondary
/// action on each side (like a camera), and one line underneath. The sides fade while recording
/// but keep their space, so the record button never moves under a finger. When a side label would
/// not fit in two lines beside the button (very large text, a narrow phone), the sides move under
/// the line as full-width buttons.
class RecordDock extends StatelessWidget {
  const RecordDock({
    super.key,
    required this.button,
    required this.status,
    this.leading,
    this.trailing,
    this.sidesVisible = true,
    this.buttonExtent = 96,
  });

  /// The [RecordButton], [buttonExtent] across.
  final Widget button;
  final double buttonExtent;

  /// One line: "Tap to answer", or the [RecordClock] while recording.
  final Widget status;
  final DockAction? leading;
  final DockAction? trailing;
  final bool sidesVisible;

  /// Whether [label] fits beside the button in at most two lines without breaking a word.
  static bool _fits(BuildContext context, String label, double width) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    double measure(String text) {
      painter.text = TextSpan(text: text, style: PrepType.meta);
      painter.layout();
      return painter.width;
    }

    final words = label.split(' ').map(measure);
    final fits = words.every((w) => w <= width) && measure(label) <= width * 2 - Space.l;
    painter.dispose();
    return fits;
  }

  @override
  Widget build(BuildContext context) {
    final words = DefaultTextStyle.merge(textAlign: TextAlign.center, style: PrepType.titleM, child: status);
    final sides = [leading, trailing].nonNulls.toList();
    Widget side(Widget? child) => Visibility(
          visible: sidesVisible && child != null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: child ?? const SizedBox.shrink(),
        );
    return LayoutBuilder(
      builder: (context, box) {
        final sideWidth = (box.maxWidth - buttonExtent) / 2 - Space.s;
        final besideButton = sides.every((a) => _fits(context, a.label, sideWidth));
        if (!besideButton) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: button),
              const SizedBox(height: Space.s),
              words,
              for (final action in sides) ...[
                const SizedBox(height: Space.s),
                side(
                  DockAction(
                    icon: action.icon,
                    label: action.label,
                    semanticLabel: action.semanticLabel,
                    onPressed: action.onPressed,
                    wide: true,
                  ),
                ),
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
            const SizedBox(height: Space.s),
            words,
          ],
        );
      },
    );
  }
}

/// A secondary answer action beside the record button: an outlined round icon with its label
/// under it, all of it one 48 dp+ target. [wide] lays it out as a full-width outlined button.
class DockAction extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final tint = enabled ? PrepColors.text : PrepColors.text3;
    final Widget body;
    if (wide) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: PrepColors.surface1,
          border: Border.all(color: enabled ? PrepColors.text3 : PrepColors.line),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PrepIcon(icon, color: tint, size: 20),
                const SizedBox(width: Space.s),
                Flexible(child: Text(label, textAlign: TextAlign.center, style: PrepType.label.copyWith(color: tint))),
              ],
            ),
          ),
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 72, minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: PrepColors.surface1,
                  // The outline is the only edge on the page, so it uses text3 (3:1 or better).
                  shape: CircleBorder(side: BorderSide(color: enabled ? PrepColors.text3 : PrepColors.line)),
                ),
                child: SizedBox.square(dimension: 48, child: Center(child: PrepIcon(icon, color: tint, size: 22))),
              ),
              const SizedBox(height: Space.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: PrepType.meta.copyWith(color: enabled ? PrepColors.text2 : PrepColors.text3),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: FocusRing(
        child: Material(
          type: MaterialType.transparency,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.control))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onPressed, focusColor: Colors.transparent, child: body),
        ),
      ),
    );
  }
}

/// Quiet actions under the primary in a bottom bar, side by side, each centred in its half.
class QuietRow extends StatelessWidget {
  const QuietRow(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        children: [
          for (final child in children) Expanded(child: Center(child: child)),
        ],
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

/// A problem, said plainly, with what to do about it.
class ProblemNote extends StatelessWidget {
  const ProblemNote({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PrepType.titleM),
          const SizedBox(height: Space.xs),
          Text(body, style: PrepType.body),
        ],
      ),
    );
  }
}

String clock(int ms) {
  final total = (ms / 1000).floor().clamp(0, 5999);
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
