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
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import '../intake/intake_screen.dart';
import '../profile/profile_format.dart';
import '../shell/shell_scope.dart';
import '../talk/talk_screen.dart';
import '../wrapup/wrapup_screen.dart';

/// Home: the assistant on its stage talking to you, one big way into practice, the other ways to
/// practise as a row of little assistants, and what is coming up. A tab body inside the shell.
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

  Future<void> _startPractice({int questionCount = 5, bool typing = false}) async {
    if (_starting) return;
    _starting = true;
    try {
      if (!await _ensureConsent() || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => IntakeScreen(questionCount: questionCount, preferTyping: typing)),
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
      await services.voice.speak(name.isEmpty ? 'Hello! What would you like to ask?' : 'Hi $name! What would you like to ask?');
    } catch (_) {
      // No voice on this phone: go straight to the conversation.
    }
    _heroLevel.rest();
    _talking = false;
    if (!mounted) return;
    setState(() => _heroMood = AssistantMood.idle);
    _openTalk();
  }

  void _openRecent(PracticeSession session) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: session, review: true)));
  }

  void _goTo(ShellTab tab) => ShellScope.of(context).goTo(tab);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final screen = MediaQuery.sizeOf(context);
    final heroSize = (screen.height * 0.34).clamp(200.0, 360.0);
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
              padding: const EdgeInsets.only(top: Space.m, bottom: Space.x4),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: _Greeting(profile: profile),
                ),
                const SizedBox(height: Space.l),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: _Stage(
                    look: look,
                    mood: _heroMood,
                    level: _heroLevel,
                    size: heroSize,
                    line: _bubbleLine(profile, look),
                    onTap: _tapAssistant,
                  ),
                ),
                const SizedBox(height: Space.l),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: _StartButton(glow: look.tone, onPressed: () => _startPractice()),
                ),
                const SizedBox(height: Space.x3),
                _SectionTitle('Ways to practise'),
                const SizedBox(height: Space.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ModeCard(
                          key: const ValueKey('quick-question'),
                          look: look,
                          mood: AssistantMood.thinking,
                          title: 'Quick question',
                          meta: '1 question',
                          onTap: () => _startPractice(questionCount: 1),
                        ),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: _ModeCard(
                          key: const ValueKey('talk-to-assistant'),
                          look: look,
                          mood: AssistantMood.speaking,
                          title: 'Talk to ${look.name}',
                          meta: 'Ask anything',
                          onTap: _openTalk,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.x3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: _InterviewCard(profile: profile, glow: look.tone, onSet: () => _goTo(ShellTab.profile)),
                ),
                if (last != null) ...[
                  const SizedBox(height: Space.l),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: _RecentCard(session: last, glow: look.tone, onTap: () => _openRecent(last)),
                  ),
                ],
                const SizedBox(height: Space.l),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: _TipCard(glow: look.tone),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _bubbleLine(Profile profile, AssistantLook look) {
    final days = profile.daysUntilInterview(DateTime.now());
    if (days != null && days >= 0 && days <= 14) {
      return days == 0 ? 'Big day! Quick warm-up?' : 'Let\'s get you ready.';
    }
    return 'Tap me to talk.';
  }
}

/// "Hi, Alex" and one short line under it.
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
          child: Text(name.isEmpty ? 'Hi there' : 'Hi, $name', key: const ValueKey('home-greeting'), style: PrepType.display),
        ),
        const SizedBox(height: Space.xxs),
        Text(line, key: const ValueKey('home-countdown'), style: PrepType.body),
      ],
    );
  }
}

/// The assistant on a lit stage: a soft pool of its own colour behind it and a speech bubble.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.look,
    required this.mood,
    required this.level,
    required this.size,
    required this.line,
    required this.onTap,
  });

  final AssistantLook look;
  final AssistantMood mood;
  final ValueListenable<double> level;
  final double size;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glow = look.tone;
    return Semantics(
      button: true,
      label: 'Talk with ${look.name}',
      excludeSemantics: true,
      onTap: onTap,
      child: FocusRing(
        radius: Radii.sheet,
        child: Material(
          color: PrepColors.surface1,
          borderRadius: BorderRadius.circular(Radii.sheet),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('home-assistant'),
            onTap: onTap,
            child: SizedBox(
              height: size + Space.xxl,
              child: Stack(
                children: [
                  // The stage light: the assistant's colour pooled behind it.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.25, -0.1),
                          radius: 0.9,
                          colors: [glow.withValues(alpha: 0.22), glow.withValues(alpha: 0.04), glow.withValues(alpha: 0)],
                          stops: const [0, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -size * 0.04,
                    bottom: Space.s,
                    child: AssistantAvatar(look: look, size: size, mood: mood, level: level),
                  ),
                  Positioned(
                    left: Space.xl,
                    top: Space.xl,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: _Bubble(text: line, glow: glow, name: look.name),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.glow, required this.name});

  final String text;
  final Color glow;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: PrepType.label.copyWith(color: glow)),
        const SizedBox(height: Space.xs),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: PrepColors.surface2,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(Radii.control),
              bottomLeft: Radius.circular(Radii.control),
              bottomRight: Radius.circular(Radii.control),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
            child: Text(text, style: PrepType.bodyLMedium),
          ),
        ),
      ],
    );
  }
}

/// The one big action: a pill in the assistant's colour.
class _StartButton extends StatelessWidget {
  const _StartButton({required this.glow, required this.onPressed});

  final Color glow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start practice, 5 questions',
      excludeSemantics: true,
      onTap: onPressed,
      child: FocusRing(
        radius: 32,
        child: Material(
          color: glow,
          borderRadius: BorderRadius.circular(32),
          child: InkWell(
            key: const ValueKey('start-practice'),
            borderRadius: BorderRadius.circular(32),
            onTap: onPressed,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  const SizedBox(width: Space.s),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: PrepColors.bg, shape: BoxShape.circle),
                    child: Center(child: PrepIcon(PrepIcons.mic, color: glow, size: 22)),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start practice', style: PrepType.button.copyWith(color: PrepColors.bg, fontSize: 17)),
                        Text('5 questions · 10 min', style: PrepType.caption.copyWith(color: PrepColors.bg.withValues(alpha: 0.72))),
                      ],
                    ),
                  ),
                  const PrepIcon(PrepIcons.chevron, color: PrepColors.bg, size: 20),
                  const SizedBox(width: Space.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Semantics(header: true, child: Text(text, style: PrepType.titleL)),
    );
  }
}

/// One way to practise, shown by a little assistant doing that thing.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.look,
    required this.mood,
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final AssistantLook look;
  final AssistantMood mood;
  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Semantics(
        button: true,
        label: '$title, $meta',
        excludeSemantics: true,
        onTap: onTap,
        child: FocusRing(
          radius: Radii.card,
          child: Material(
            color: PrepColors.surface1,
            borderRadius: BorderRadius.circular(Radii.card),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 118,
                      width: double.infinity,
                      color: look.tone.withValues(alpha: 0.08),
                      alignment: Alignment.bottomCenter,
                      child: AssistantAvatar(look: look, size: 112, mood: mood, hud: false),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                      child: Text(title, style: PrepType.bodyLMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.xxs, Space.l, Space.l),
                      child: Text(meta, style: PrepType.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Days to the interview as one big number, or a nudge to add the date.
class _InterviewCard extends StatelessWidget {
  const _InterviewCard({required this.profile, required this.glow, required this.onSet});

  final Profile profile;
  final Color glow;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final days = profile.daysUntilInterview(DateTime.now());
    final role = profile.targetRole.trim();
    final upcoming = days != null && days >= 0;
    final Widget body;
    if (upcoming) {
      body = Row(
        children: [
          Text('$days', style: PrepType.display.copyWith(fontSize: 44, height: 1, color: glow)),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(days == 1 ? 'day to your interview' : 'days to your interview', style: PrepType.bodyLMedium),
                if (role.isNotEmpty) Text(role, style: PrepType.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: glow.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Center(child: PrepIcon(PrepIcons.calendar, color: glow, size: 22)),
          ),
          const SizedBox(width: Space.l),
          Expanded(child: Text('Add your interview date', style: PrepType.bodyLMedium)),
          const PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
        ],
      );
    }
    return Semantics(
      button: !upcoming,
      label: upcoming ? '$days days to your interview${role.isEmpty ? '' : ', $role'}' : 'Add your interview date',
      excludeSemantics: true,
      onTap: upcoming ? null : onSet,
      child: Material(
        color: PrepColors.surface1,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          key: const ValueKey('interview-card'),
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: upcoming ? onSet : onSet,
          child: Padding(padding: const EdgeInsets.all(Space.xl), child: body),
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.session, required this.glow, required this.onTap});

  final PracticeSession session;
  final Color glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = session.questions.length;
    final answered = session.answers.length;
    final date = shortDate(session.startedAt, DateTime.now());
    return Semantics(
      button: true,
      label: 'Last practice, ${session.jobTitle}, $answered of $total answered, $date',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: const ValueKey('recent-card'),
        color: PrepColors.surface1,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Last practice', style: PrepType.label.copyWith(color: PrepColors.text2))),
                    Text(date, style: PrepType.meta),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(session.jobTitle, style: PrepType.titleM, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.m),
                // One segment per question: lit when answered.
                Row(
                  children: [
                    for (var i = 0; i < total; i++) ...[
                      if (i > 0) const SizedBox(width: Space.xs),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: session.answers.containsKey(i) ? glow : PrepColors.line,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(
                  session.wrapup != null ? '$answered of $total answered · Notes ready' : '$answered of $total answered',
                  style: PrepType.meta,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One short tip, a different one each day.
class _TipCard extends StatelessWidget {
  const _TipCard({required this.glow});

  final Color glow;

  static const _tips = [
    'Start with the point, then one example.',
    'Say "I", not "we", for your part.',
    'End every story with the result.',
    'Pause instead of saying "um".',
    'Have one question ready for them.',
    'Slow down on your first answer.',
    'Keep answers under two minutes.',
    'Use numbers when you can.',
    'Know why you want this job.',
    'Practise out loud, not in your head.',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final day = DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(2026)).inDays;
    final tip = _tips[day % _tips.length];
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: glow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrepIcon(PrepIcons.target, color: glow, size: 22),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tip of the day', style: PrepType.label.copyWith(color: glow)),
                const SizedBox(height: Space.xxs),
                Text(tip, style: PrepType.bodyLMedium),
              ],
            ),
          ),
        ],
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
