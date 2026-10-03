import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/services.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/robot_stage.dart';
import '../../design/tokens.dart';
import '../drills/drill_content.dart';
import '../drills/drill_lesson_screen.dart';
import '../drills/skill_path.dart';
import '../consent/consent_sheet.dart';
import '../intake/intake_screen.dart';
import '../shell/shell_scope.dart';
import '../talk/talk_screen.dart';
import '../wrapup/wrapup_screen.dart';

enum _Segment { speak, skills }

/// The Practice tab: Speak (the mock interview on a metal stage, then the other ways to practice)
/// or Skills (the drill path). The shell owns the tab bar; this keeps its own top [SafeArea].
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  // Guards a rapid double tap from pushing two intakes at once.
  bool _busy = false;
  _Segment _segment = _Segment.speak;

  /// Mock interview, Quick and Type all land here: they ask for consent once, then open the
  /// intake with whichever parameters name the mode.
  Future<void> _openIntake({bool preferTyping = false, int questionCount = 3}) async {
    if (_busy) return;
    _busy = true;
    try {
      final services = AppScope.of(context);
      if (!await services.consent.accepted()) {
        if (!mounted) return;
        if (!await showConsentSheet(context)) return;
        await services.consent.accept();
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => IntakeScreen(preferTyping: preferTyping, questionCount: questionCount),
        ),
      );
    } finally {
      _busy = false;
    }
  }

  void _openLesson(DrillSkill skill, DrillLesson lesson) {
    final services = AppScope.of(context);
    openDrillLesson(
      context,
      skill: skill,
      lesson: lesson,
      look: services.assistant.value,
      progress: services.drills,
      onPracticeAloud: () => _openIntake(questionCount: 1),
    );
  }

  void _openTalk() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TalkScreen()));
  }

  void _openNotes() {
    final last = AppScope.of(context).sessions.last;
    if (last == null) {
      ShellScope.of(context).goTo(ShellTab.history);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: last, review: true)));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Transparent: the shell's lit room shows through behind the glass.
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: services.assistant,
        builder: (context, _) {
          final look = services.assistant.value;
          return ListView(
            padding: EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, floatingTabBarInset(context)),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Practice',
                  style: PrepType.display,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6),
                ),
              ),
              const SizedBox(height: Space.xl),
              MetalSegments(
                labels: const ['Speak', 'Skills'],
                selected: _segment.index,
                keys: const [ValueKey('practice-speak'), ValueKey('practice-skills')],
                onSelect: (i) => setState(() => _segment = _Segment.values[i]),
              ),
              const SizedBox(height: Space.xxl),
              AnimatedSwitcher(
                duration: reduce ? Duration.zero : Motion.fade,
                switchInCurve: Motion.standard,
                switchOutCurve: Motion.standard,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: switch (_segment) {
                  _Segment.speak => _SpeakModes(
                    key: const ValueKey('speak'),
                    look: look,
                    onMock: () => _openIntake(),
                    onQuick: () => _openIntake(questionCount: 1),
                    onType: () => _openIntake(preferTyping: true),
                    onTalk: _openTalk,
                    onNotes: _openNotes,
                  ),
                  _Segment.skills => SkillPath(
                    key: const ValueKey('skills'),
                    progress: services.drills,
                    onOpenLesson: _openLesson,
                  ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The mock interview as the hero, then the other spoken and typed ways in, as one metal list.
class _SpeakModes extends StatelessWidget {
  const _SpeakModes({
    super.key,
    required this.look,
    required this.onMock,
    required this.onQuick,
    required this.onType,
    required this.onTalk,
    required this.onNotes,
  });

  final AssistantLook look;
  final VoidCallback onMock;
  final VoidCallback onQuick;
  final VoidCallback onType;
  final VoidCallback onTalk;
  final VoidCallback onNotes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MockCard(look: look, onTap: onMock),
        const SizedBox(height: Space.m),
        MetalCard(
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(Radii.card),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _ModeRow(
                  key: const ValueKey('mode-quick'),
                  icon: PrepIcons.clock,
                  title: 'Quick',
                  meta: '1 question',
                  spoken: 'Quick practice, 1 question',
                  onTap: onQuick,
                ),
                const Hairline(indent: _ModeRow.textInset),
                _ModeRow(
                  key: const ValueKey('mode-typing'),
                  icon: PrepIcons.keyboard,
                  title: 'Type',
                  meta: '3 questions',
                  spoken: 'Type your answers, 3 questions',
                  onTap: onType,
                ),
                const Hairline(indent: _ModeRow.textInset),
                _ModeRow(
                  key: const ValueKey('mode-talk'),
                  icon: PrepIcons.chat,
                  title: 'Ask ${look.name}',
                  spoken: 'Ask ${look.name} about interviews',
                  onTap: onTalk,
                ),
                const Hairline(indent: _ModeRow.textInset),
                _ModeRow(
                  key: const ValueKey('mode-notes'),
                  icon: PrepIcons.write,
                  title: 'Notes',
                  spoken: 'Your notes',
                  onTap: onNotes,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The main way to practice: its name, a big "3" for the questions and the time, a play disc, and
/// the coach standing on its pedestal at the right.
class _MockCard extends StatelessWidget {
  const _MockCard({required this.look, required this.onTap});

  final AssistantLook look;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    return MetalTile(
      key: const ValueKey('mode-mock'),
      hero: true,
      radius: Radii.sheet,
      semanticLabel: 'Mock interview, 3 questions, about 6 minutes',
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(Space.xxl, Space.xxl, Space.m, Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mock interview', style: PrepType.titleL),
                const SizedBox(height: Space.s),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: Space.m,
                  runSpacing: Space.xs,
                  children: [
                    Text('3', style: PrepType.numeral, textScaler: big),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s),
                      child: Text('questions · 6 min', style: PrepType.meta),
                    ),
                  ],
                ),
                const SizedBox(height: Space.m),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: PrepColors.accent, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Padding(
                    // The triangle's weight sits left of its box; nudge it to look centred.
                    padding: const EdgeInsets.only(left: 2),
                    child: PrepIcon(PrepIcons.play, color: PrepColors.onAccent, size: 22),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s),
          RobotStage(look: look, robotSize: 124, dial: false),
        ],
      ),
    );
  }
}

/// One way to practice: its icon on a raised metal disc, a one or two word title, an optional count,
/// a chevron.
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    super.key,
    required this.icon,
    required this.title,
    required this.spoken,
    required this.onTap,
    this.meta,
  });

  /// Where the titles start, so the hairlines between rows line up with them.
  static const double textInset = Space.l + 40 + Space.l;

  final PrepIcons icon;
  final String title;
  final String? meta;
  final String spoken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = this.meta;
    return Semantics(
      container: true,
      button: true,
      label: spoken,
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        radius: Radii.control,
        gap: -Space.xs,
        child: InkWell(
          onTap: onTap,
          focusColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.xl, Space.m),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: PrepColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: PrepColors.rimLight),
                    ),
                    alignment: Alignment.center,
                    child: PrepIcon(icon, color: PrepColors.text, size: 20),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(child: Text(title, style: PrepType.titleM)),
                  if (meta != null) ...[
                    const SizedBox(width: Space.m),
                    // Fills its share and sits at the end of it, so every chevron lines up.
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(meta, style: PrepType.meta, textAlign: TextAlign.end),
                      ),
                    ),
                  ],
                  const SizedBox(width: Space.s),
                  PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
