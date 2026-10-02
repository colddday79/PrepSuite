import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/profile.dart';
import '../../app/services.dart';
import '../../app/session.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/practice_chrome.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../drills/drill_content.dart';
import '../drills/drill_lesson_screen.dart';
import '../drills/skill_path.dart';
import '../consent/consent_sheet.dart';
import '../intake/intake_screen.dart';
import '../profile/profile_format.dart';
import '../talk/talk_screen.dart';
import '../wrapup/wrapup_screen.dart';

/// Home, kept calm: a greeting, the coach on a plain card, one Start practice, then only what is
/// useful right now (the next drill and the last practice). A tab body inside the shell.
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

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([services.profile, services.sessions, services.assistant]),
          builder: (context, _) {
            final profile = services.profile.value;
            final look = services.assistant.value;
            final last = services.sessions.last;
            return ListView(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.x4),
              children: [
                _Greeting(profile: profile),
                const SizedBox(height: Space.xxl),
                _CoachCard(look: look, mood: _heroMood, level: _heroLevel, onTap: _tapAssistant),
                const SizedBox(height: Space.l),
                PrimaryButton(
                  'Start practice',
                  key: const ValueKey('start-practice'),
                  icon: PrepIcons.mic,
                  onPressed: () => _startPractice(),
                ),
                const SizedBox(height: Space.s),
                Text('3 questions · about 6 minutes', style: PrepType.meta, textAlign: TextAlign.center),
                const SizedBox(height: Space.x3),
                const _SectionTitle('Skills'),
                const SizedBox(height: Space.m),
                NextLessonCard(progress: services.drills, onOpen: _openLesson),
                if (last != null) ...[
                  const SizedBox(height: Space.x3),
                  const _SectionTitle('Last practice'),
                  const SizedBox(height: Space.m),
                  _RecentCard(session: last, onTap: () => _openRecent(last)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "Hi, Alex" and one quiet line under it.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim();
    final line = interviewCountdown(profile, DateTime.now()) ?? 'Ready when you are.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            name.isEmpty ? 'Hi there' : 'Hi, $name',
            key: const ValueKey('home-greeting'),
            style: PrepType.display,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(line, key: const ValueKey('home-countdown'), style: PrepType.body),
      ],
    );
  }
}

/// The coach, at a restrained size on a plain card: its name and one line on the left, the robot on
/// the right. Tapping it says hello and opens the conversation.
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.look, required this.mood, required this.level, required this.onTap});

  final AssistantLook look;
  final AssistantMood mood;
  final ValueListenable<double> level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = (box.maxWidth * 0.5).clamp(140.0, 230.0);
        return Semantics(
          button: true,
          label: 'Talk with ${look.name}',
          excludeSemantics: true,
          onTap: onTap,
          child: FocusRing(
            radius: Radii.card,
            child: Material(
              color: PrepColors.surface1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.card),
                side: const BorderSide(color: PrepColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('home-assistant'),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.s, Space.l),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(look.name, style: PrepType.titleL),
                            const SizedBox(height: Space.xs),
                            Text('Your interview coach. Tap to ask me anything.', style: PrepType.body),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.s),
                      AssistantAvatar(look: look, size: size, mood: mood, level: level, hud: false),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(header: true, child: Text(text, style: PrepType.titleM));
}

/// The last practice: the job, how far it got and when, with one quiet progress track.
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.session, required this.onTap});

  final PracticeSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = session.questions.length;
    final answered = session.answers.length;
    final date = shortDate(session.startedAt, DateTime.now());
    final status = session.wrapup != null ? '$answered of $total answered · Notes ready' : '$answered of $total answered';
    return Semantics(
      button: true,
      label: 'Last practice, ${session.jobTitle}, $status, $date',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: const ValueKey('recent-card'),
        color: PrepColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: const BorderSide(color: PrepColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.jobTitle, style: PrepType.titleM, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Space.xxs),
                      Text('$status · $date', style: PrepType.meta),
                      const SizedBox(height: Space.m),
                      ProgressTrack(
                        value: total == 0 ? 0 : answered / total,
                        label: '$answered of $total answered',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.l),
                const PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Interview in 5 days" for Home, or null when there is no upcoming date.
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
