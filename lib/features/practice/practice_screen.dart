import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../drills/drill_content.dart';
import '../drills/drill_lesson_screen.dart';
import '../drills/skill_path.dart';
import '../consent/consent_sheet.dart';
import '../intake/intake_screen.dart';
import '../shell/shell_scope.dart';
import '../talk/talk_screen.dart';
import '../wrapup/wrapup_screen.dart';

/// The body of the Practice tab: the ways to practise out loud as one plain list, then the skill
/// drills. The bottom navigation bar and the tab's own [Scaffold] belong to the app shell; this
/// widget only needs its own top [SafeArea].
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  // Guards a rapid double tap from pushing two intakes at once.
  bool _busy = false;

  /// Mock interview, Quick question and typing all land here: they ask for consent
  /// once, then open the intake with whichever parameters name the mode.
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
    return ColoredBox(
      color: PrepColors.bg,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: services.assistant,
          builder: (context, _) {
            final look = services.assistant.value;
            return ListView(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.x4),
              children: [
                Semantics(header: true, child: Text('Practice', style: PrepType.display)),
                const SizedBox(height: Space.xxl),
                const _SectionTitle('Out loud'),
                const SizedBox(height: Space.m),
                _Group(
                  children: [
                    LinkRow(
                      key: const ValueKey('mode-mock'),
                      icon: PrepIcons.mic,
                      title: 'Mock interview',
                      meta: '3 questions · about 6 minutes',
                      onTap: () => _openIntake(),
                    ),
                    LinkRow(
                      key: const ValueKey('mode-quick'),
                      icon: PrepIcons.clock,
                      title: 'Quick question',
                      meta: '1 question · about 2 minutes',
                      onTap: () => _openIntake(questionCount: 1),
                    ),
                    LinkRow(
                      key: const ValueKey('mode-typing'),
                      icon: PrepIcons.keyboard,
                      title: 'Type your answers',
                      meta: 'When you can\'t talk right now',
                      onTap: () => _openIntake(preferTyping: true),
                    ),
                    LinkRow(
                      key: const ValueKey('mode-talk'),
                      icon: PrepIcons.chat,
                      title: 'Ask ${look.name}',
                      meta: 'Questions about interviews',
                      onTap: _openTalk,
                    ),
                    LinkRow(
                      key: const ValueKey('mode-notes'),
                      icon: PrepIcons.write,
                      title: 'Your notes',
                      meta: 'Read before you go in',
                      onTap: _openNotes,
                    ),
                  ],
                ),
                const SizedBox(height: Space.x3),
                const _SectionTitle('Skills'),
                const SizedBox(height: Space.m),
                SkillPath(progress: services.drills, onOpenLesson: _openLesson),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(header: true, child: Text(text, style: PrepType.titleM));
}

/// Rows on one plain card, separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PrepColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: PrepColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: Space.gutter + 24 + Space.l, color: PrepColors.line),
            children[i],
          ],
        ],
      ),
    );
  }
}
