import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/profile.dart';
import '../../app/services.dart';
import '../../app/session.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/robot_stage.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import '../drills/drill_content.dart';
import '../drills/drill_lesson_screen.dart';
import '../drills/drill_progress.dart';
import '../intake/intake_screen.dart';
import '../profile/initial_disc.dart';
import '../profile/profile_format.dart';
import '../shell/shell_scope.dart';
import '../talk/talk_screen.dart';
import '../wrapup/wrapup_screen.dart';

/// Big type (the greeting, numerals) grows with the system text size only this far: it starts
/// large, and past this it would push everything else off a phone (Android scales big text less too).
const double _bigScale = 1.6;

/// Thin numerals at [size], for counts and stats. Proportional figures: the font's tabular zero
/// is slashed, which reads as a letter at this size.
TextStyle _thin(double size) => PrepType.numeral.copyWith(
  fontSize: size,
  height: (size + 4) / size,
  letterSpacing: -0.02 * size,
  fontFeatures: const [],
);

/// Home: the coach as a lit product on its dial, one Start practice, this week in numbers, then the
/// next skill and the last practice. A tab body inside the shell.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _heroLevel = LevelMix();
  AppServices? _services;
  AssistantMood _heroMood = AssistantMood.idle;
  bool _starting = false;
  bool _talking = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    if (!_listening) {
      _listening = true;
      _heroLevel.listenTo(_services!.voice.level);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_talking) _services?.voice.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_talking) _services?.voice.stop();
    _heroLevel.dispose();
    super.dispose();
  }

  Future<bool> _ensureConsent() async {
    final services = _services!;
    if (await services.consent.accepted()) return true;
    if (!mounted) return false;
    if (!await showConsentSheet(context)) return false;
    await services.consent.accept();
    return true;
  }

  Future<void> _startPractice({int questionCount = 3, bool typing = false}) async {
    if (_starting) return;
    _starting = true;
    try {
      if (!await _ensureConsent() || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => IntakeScreen(questionCount: questionCount, preferTyping: typing),
        ),
      );
    } finally {
      _starting = false;
    }
  }

  void _openTalk() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TalkScreen()));
  }

  /// Tapping the assistant: it lights up, says hello out loud, then opens the conversation.
  Future<void> _tapAssistant() async {
    if (_talking) return;
    _talking = true;
    final services = _services!;
    setState(() => _heroMood = AssistantMood.happy);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) {
      _talking = false;
      return;
    }
    final name = services.profile.value.name.trim();
    setState(() => _heroMood = AssistantMood.speaking);
    try {
      await services.voice.speak(
        name.isEmpty ? 'Hello! What would you like to ask?' : 'Hi $name! What would you like to ask?',
      );
    } catch (_) {
      // No voice on this phone: go straight to the conversation.
    }
    _heroLevel.rest();
    _talking = false;
    if (!mounted) return;
    setState(() => _heroMood = AssistantMood.idle);
    _openTalk();
  }

  void _openLesson(DrillSkill skill, DrillLesson lesson) {
    final services = _services!;
    openDrillLesson(
      context,
      skill: skill,
      lesson: lesson,
      look: services.assistant.value,
      progress: services.drills,
      onPracticeAloud: () => _startPractice(questionCount: 1),
    );
  }

  void _openRecent(PracticeSession session) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: session, review: true)));
  }

  void _openProfile() => ShellScope.maybeOf(context)?.goTo(ShellTab.profile);

  /// About half the screen for the coach, but on a short phone never so much that Start falls
  /// under the tab bar (down to [minStage]).
  double _stageHeight(BuildContext context) {
    const minStage = 240.0;
    const maxStage = 520.0;
    final media = MediaQuery.of(context);
    final scaler = media.textScaler;
    final screen = media.size.height;
    final target = math.min(screen * 0.5, maxStage);
    final header = math.max(48.0, scaler.clamp(maxScaleFactor: _bigScale).scale(36) + Space.xxs + scaler.scale(18));
    final above = Space.l + header + Space.xl;
    final below = Space.xl + math.max(64.0, scaler.scale(20) + scaler.scale(18) + 2 * Space.m) + Space.s;
    final barTop = screen - floatingTabBarInset(context) + Space.l;
    final fit = barTop - media.padding.top - above - below;
    return math.max(math.min(target, fit), math.min(target, minStage));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    // Transparent: the shell's lit room shows through behind the glass.
    return ListenableBuilder(
      listenable: Listenable.merge([services.profile, services.sessions, services.assistant, services.drills]),
      builder: (context, _) {
        final profile = services.profile.value;
        final now = DateTime.now();
        final countdown = interviewCountdown(profile, now);
        final stage = _stageHeight(context);
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, floatingTabBarInset(context)),
            children: [
              _Header(
                name: profile.name.trim(),
                line: countdown ?? shortDate(now, now),
                lineKey: ValueKey(countdown == null ? 'home-date' : 'home-countdown'),
                onProfile: _openProfile,
              ),
              const SizedBox(height: Space.xl),
              _CoachStage(
                look: services.assistant.value,
                mood: _heroMood,
                level: _heroLevel,
                height: stage,
                done: services.drills.doneTotal,
                total: services.drills.lessonCount,
                onTap: _tapAssistant,
              ),
              const SizedBox(height: Space.xl),
              _StartButton(key: const ValueKey('start-practice'), onPressed: () => _startPractice()),
              const SizedBox(height: Space.xxl),
              _WeekCard(week: _Week.of(services.sessions.history, now)),
              const SizedBox(height: Space.m),
              _NextTiles(
                drills: services.drills,
                last: services.sessions.last,
                onLesson: _openLesson,
                onRecent: _openRecent,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Hi, Alex" with today's date (or the interview countdown) under it, and the avatar that opens
/// Profile.
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.line, required this.lineKey, required this.onProfile});

  final String name;
  final String line;
  final Key lineKey;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    const shape = CircleBorder();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  name.isEmpty ? 'Hi there' : 'Hi, $name',
                  key: const ValueKey('home-greeting'),
                  style: PrepType.display,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _bigScale),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: Space.xxs),
              Text(line, key: lineKey, style: PrepType.meta, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: Space.m),
        Semantics(
          button: true,
          label: 'Profile',
          onTap: onProfile,
          excludeSemantics: true,
          child: Tooltip(
            message: 'Profile',
            excludeFromSemantics: true,
            child: FocusRing(
              radius: 24,
              child: Material(
                type: MaterialType.transparency,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('home-profile'),
                  onTap: onProfile,
                  customBorder: shape,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(child: InitialDisc(name: name, size: 44, ring: PrepColors.accentDeep)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The coach as a lit product: the robot on its pedestal inside a ticked dial whose accent arc is
/// the skill lessons done, a little right of centre. Its name sits in the top corner and the count
/// in the bottom one, and the dial is sized and placed to keep clear of both. Tapping it says
/// hello and opens Talk.
class _CoachStage extends StatelessWidget {
  const _CoachStage({
    required this.look,
    required this.mood,
    required this.level,
    required this.height,
    required this.done,
    required this.total,
    required this.onTap,
  });

  final AssistantLook look;
  final AssistantMood mood;
  final ValueListenable<double> level;
  final double height;
  final int done;
  final int total;
  final VoidCallback onTap;

  static const String _tagline = 'Your coach';
  static const double _pad = Space.xl;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final big = scaler.clamp(maxScaleFactor: _bigScale);
    final count = '$done/$total';
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final name = _measure([(look.name, PrepType.titleL, scaler), (_tagline, PrepType.meta, scaler)], width - 2 * _pad);
        final tally = _measure([(count, _thin(40), big), ('Skills', PrepType.meta, scaler)], width - 2 * _pad);
        final h = math.max(height, _pad + name.height + Space.l + tally.height + _pad);
        final place = _placeDial(Size(width, h), [
          Rect.fromLTWH(_pad, _pad, name.width, name.height),
          Rect.fromLTWH(_pad, h - _pad - tally.height, tally.width, tally.height),
        ]);
        return Stack(
          children: [
            MetalTile(
              key: const ValueKey('home-assistant'),
              hero: true,
              radius: Radii.sheet,
              padding: EdgeInsets.zero,
              semanticLabel: 'Talk with ${look.name}',
              onTap: onTap,
              child: SizedBox(
                height: h,
                child: Stack(
                  children: [
                    Positioned(
                      left: place.centre.dx - place.size / 2,
                      top: place.centre.dy - place.size / 2,
                      child: RobotStage(
                        look: look,
                        robotSize: place.size,
                        mood: mood,
                        level: level,
                        progress: total == 0 ? 0 : done / total,
                      ),
                    ),
                    Positioned(
                      left: _pad,
                      top: _pad,
                      right: _pad,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(look.name, style: PrepType.titleL),
                          const SizedBox(height: Space.xxs),
                          Text(_tagline, style: PrepType.meta),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: _pad,
              bottom: _pad,
              child: IgnorePointer(
                child: Semantics(
                  label: '$done of $total skill lessons done',
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(count, style: _thin(40), textScaler: big),
                        const SizedBox(height: Space.xxs),
                        Text('Skills', style: PrepType.meta),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The size of [lines] stacked with a small gap.
  static Size _measure(List<(String, TextStyle, TextScaler)> lines, double maxWidth) {
    var width = 0.0;
    var height = 0.0;
    for (final (i, (text, style, scaler)) in lines.indexed) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: math.max(0, maxWidth));
      width = math.max(width, painter.width);
      height += painter.height + (i > 0 ? Space.xxs : 0);
      painter.dispose();
    }
    return Size(width, height);
  }

  /// The largest dial that fits [card] (up to 86% of its height) with its ticks clear of
  /// [keepClear], placed nearest a little right of centre and the vertical middle.
  static ({double size, Offset centre}) _placeDial(Size card, List<Rect> keepClear) {
    const margin = Space.s;
    const step = 4.0;
    final midY = card.height / 2;
    final aimX = card.width * 0.58;
    for (var size = math.min(card.height * 0.86, card.width - 2 * margin); size >= 96; size -= step) {
      // A hair of air between the outer ticks and the text.
      final reach = size / 2 + Space.xs;
      final minX = math.max(card.width / 2, size / 2 + margin);
      final maxX = card.width - size / 2 - margin;
      final minY = size / 2 + margin;
      final maxY = card.height - size / 2 - margin;
      if (maxX < minX || maxY < minY) continue;
      final xs = [for (var x = minX; x <= maxX; x += step) x, maxX]
        ..sort((a, b) => (a - aimX).abs().compareTo((b - aimX).abs()));
      for (final x in xs) {
        // Each text box rules out a band of heights for the centre at this x.
        final blocked = <(double, double)>[];
        for (final box in keepClear) {
          final dx = x < box.left ? box.left - x : (x > box.right ? x - box.right : 0.0);
          if (dx >= reach) continue;
          final dy = math.sqrt(reach * reach - dx * dx);
          blocked.add((box.top - dy, box.bottom + dy));
        }
        final ys = [midY, for (final (top, bottom) in blocked) ...[top, bottom]]
            .map((y) => y.clamp(minY, maxY))
            .toList()
          ..sort((a, b) => (a - midY).abs().compareTo((b - midY).abs()));
        for (final y in ys) {
          if (blocked.every((band) => y <= band.$1 || y >= band.$2)) {
            return (size: size, centre: Offset(x, y));
          }
        }
      }
    }
    // Very large text: a small dial on the right, centred.
    final size = math.max(48.0, math.min(96.0, card.height - 2 * margin));
    return (size: size, centre: Offset(card.width - size / 2 - margin, midY));
  }
}

/// The one main action: a tall accent pill with the mic in a darker circle, "Start practice" over
/// "3 questions", and three chevrons trailing off to the right. Pressing darkens it and settles it
/// a little (no scale when the system asks for less motion).
class _StartButton extends StatefulWidget {
  const _StartButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  static const _shape = StadiumBorder();
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final ink = PrepColors.onAccent;
    final fill = _pressed ? Color.lerp(PrepColors.accent, const Color(0xFF000000), 0.12)! : PrepColors.accent;
    final duration = _pressed ? Motion.press : Motion.fade;
    return Semantics(
      container: true,
      button: true,
      label: 'Start practice, 3 questions',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusRing(
        radius: 32,
        child: AnimatedScale(
          scale: _pressed && !still ? Motion.pressScale : 1,
          duration: duration,
          curve: Motion.standard,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: fill),
            duration: duration,
            curve: Motion.standard,
            builder: (context, color, child) => DecoratedBox(
              decoration: ShapeDecoration(color: color, shape: _shape),
              child: child,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onPressed,
                onHighlightChanged: (down) {
                  if (down != _pressed) setState(() => _pressed = down);
                },
                customBorder: _shape,
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.xl, Space.s),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: ink.withValues(alpha: 0.12), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: PrepIcon(PrepIcons.mic, color: ink, size: 22),
                        ),
                        const SizedBox(width: Space.m + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Start practice', style: PrepType.button.copyWith(color: ink)),
                              Text('3 questions', style: PrepType.meta.copyWith(color: ink.withValues(alpha: 0.8))),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.s),
                        // Three chevrons trailing off, drawn tight like ">>>".
                        for (final alpha in const [0.9, 0.55, 0.25])
                          ExcludeSemantics(
                            child: Align(
                              widthFactor: 0.62,
                              child: PrepIcon(PrepIcons.chevron, color: ink.withValues(alpha: alpha), size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// This week's practice from the saved history (Monday to today): sessions, answers and days, then
/// answers per day as bars. Real numbers only.
class _Week {
  const _Week(this.perDay, this.today, this.sessions, this.days);

  factory _Week.of(List<PracticeRecord> history, DateTime now) {
    // Calendar days in UTC, so a daylight saving change can't shift a practice into another day.
    final monday = DateTime.utc(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final perDay = List<int>.filled(7, 0);
    final active = <int>{};
    var sessions = 0;
    for (final record in history) {
      final start = record.startedAt.toLocal();
      final day = DateTime.utc(start.year, start.month, start.day).difference(monday).inDays;
      if (day < 0 || day > 6) continue;
      sessions++;
      perDay[day] += record.answered;
      active.add(day);
    }
    return _Week(perDay, now.weekday - 1, sessions, active.length);
  }

  final List<int> perDay;

  /// Monday is 0.
  final int today;
  final int sessions;
  final int days;

  int get answers => perDay.fold(0, (sum, n) => sum + n);

  static const _names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  String get spoken {
    final daily = [for (var i = 0; i <= today; i++) '${_names[i]} ${perDay[i]}'].join(', ');
    return 'This week: $sessions ${sessions == 1 ? 'session' : 'sessions'}, $answers '
        '${answers == 1 ? 'answer' : 'answers'}, $days ${days == 1 ? 'day' : 'days'}. Answers by day: $daily.';
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week});

  final _Week week;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: week.spoken,
      excludeSemantics: true,
      child: MetalCard(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('This week', style: PrepType.titleM),
            const SizedBox(height: Space.l),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Stat(value: week.sessions, label: 'Sessions'),
                  const _Rule(),
                  _Stat(value: week.answers, label: 'Answers'),
                  const _Rule(),
                  _Stat(value: week.days, label: 'Days'),
                ],
              ),
            ),
            const SizedBox(height: Space.xl),
            _WeekBars(perDay: week.perDay, today: week.today),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: _thin(32),
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _bigScale),
          ),
          const SizedBox(height: Space.xxs),
          Text(label, style: PrepType.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// The hairline between two stats.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: SizedBox(width: 1, child: ColoredBox(color: PrepColors.line)),
    );
  }
}

/// Answers per day, Monday to Sunday: today's bar in the accent, the rest quiet on a hairline
/// track. A day with none shows a short stub; days still to come show only the track.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.perDay, required this.today});

  final List<int> perDay;
  final int today;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    // A single answer never fills the track.
    final peak = math.max(3, perDay.reduce(math.max));
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _bigScale);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 64,
                  width: 8,
                  child: CustomPaint(
                    painter: _BarPainter(
                      fraction: i > today ? null : perDay[i] / peak,
                      color: i == today ? PrepColors.accent : PrepColors.text3,
                      track: PrepColors.line,
                    ),
                  ),
                ),
                const SizedBox(height: Space.s),
                Text(
                  _letters[i],
                  style: PrepType.caption.copyWith(color: i == today ? PrepColors.text : PrepColors.text3),
                  textScaler: scaler,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({required this.fraction, required this.color, required this.track});

  /// 0..1 of the track, or null for a day still to come.
  final double? fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.width / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius), Paint()..color = track);
    final f = fraction;
    if (f == null) return;
    final h = math.max(size.width / 2 + 2, size.height * f.clamp(0.0, 1.0));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, size.height - h, size.width, h), radius),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.fraction != fraction || old.color != color || old.track != track;
}

/// The next skill lesson and, once there is one, the last practice: side by side when they fit,
/// stacked on a narrow phone or with large text. Without a practice the skill spans the row.
class _NextTiles extends StatelessWidget {
  const _NextTiles({required this.drills, required this.last, required this.onLesson, required this.onRecent});

  final DrillProgressStore drills;
  final PracticeSession? last;
  final void Function(DrillSkill skill, DrillLesson lesson) onLesson;
  final ValueChanged<PracticeSession> onRecent;

  @override
  Widget build(BuildContext context) {
    final next = drills.nextLesson();
    final lesson = next ?? drills.curriculum.first.lessons.first;
    final skill = drills.skillOf(lesson);
    final skillDone = drills.doneCount(skill);
    final skillTotal = skill.lessons.length;
    final skillTile = _Tile(
      key: const ValueKey('next-skill'),
      semanticLabel: next == null
          ? 'Every skill lesson done. Practice again from the start'
          : 'Next skill: ${lesson.title}, ${skill.title}, $skillDone of $skillTotal lessons done',
      onTap: () => onLesson(skill, lesson),
      top: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(next == null ? 'All lessons done' : lesson.title, style: PrepType.titleM)),
          const SizedBox(width: Space.s),
          ArcGauge(
            value: skillTotal == 0 ? 0 : skillDone / skillTotal,
            size: 40,
            stroke: 3,
            color: PrepColors.text2,
            child: SizedBox(
              width: 22,
              height: 14,
              child: FittedBox(
                child: Text('$skillDone/$skillTotal', style: PrepType.caption.copyWith(color: PrepColors.text2)),
              ),
            ),
          ),
        ],
      ),
      bottom: Text(next == null ? 'Practice again' : 'Next skill', style: PrepType.meta),
    );
    final session = last;
    if (session == null) return skillTile;
    final answered = session.answers.length;
    final total = session.questions.length;
    final recentTile = _Tile(
      key: const ValueKey('recent-card'),
      semanticLabel:
          'Last practice, ${session.jobTitle}, $answered of $total answered, ${spokenDate(session.startedAt, DateTime.now())}',
      tapHint: 'open your notes',
      onTap: () => onRecent(session),
      top: Text(session.jobTitle, style: PrepType.titleM, maxLines: 2, overflow: TextOverflow.ellipsis),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Segments(done: answered, total: total),
          const SizedBox(height: Space.s),
          Row(
            children: [
              Expanded(child: Text('Last practice', style: PrepType.meta, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('$answered/$total', style: PrepType.label),
            ],
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        if ((box.maxWidth - Space.m) / 2 < 140 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [skillTile, const SizedBox(height: Space.m), recentTile],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: skillTile), const SizedBox(width: Space.m), Expanded(child: recentTile)],
          ),
        );
      },
    );
  }
}

/// Questions answered as short segments, the answered ones lit.
class _Segments extends StatelessWidget {
  const _Segments({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: Space.xs),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < done ? PrepColors.text2 : PrepColors.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One metal tile: its main line at the top, its short line at the bottom.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.semanticLabel,
    required this.onTap,
    required this.top,
    required this.bottom,
    this.tapHint,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget top;
  final Widget bottom;
  final String? tapHint;

  @override
  Widget build(BuildContext context) {
    return MetalTile(
      semanticLabel: semanticLabel,
      tapHint: tapHint,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.l, Space.l),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [top, const SizedBox(height: Space.l), bottom],
        ),
      ),
    );
  }
}

/// "Interview in 5 days · barista" for Home, or null when there is no upcoming date.
String? interviewCountdown(Profile profile, DateTime now) {
  final days = profile.daysUntilInterview(now);
  if (days == null || days < 0) return null;
  final role = profile.targetRole.trim();
  final when = switch (days) {
    0 => 'Interview today',
    1 => 'Interview tomorrow',
    _ => 'Interview in $days days',
  };
  return role.isEmpty ? when : '$when · $role';
}
