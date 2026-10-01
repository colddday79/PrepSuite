import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/services.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import '../intake/intake_screen.dart';
import '../shell/shell_scope.dart';
import '../talk/talk_screen.dart';
import '../wrapup/wrapup_screen.dart';

/// The body of the Practice tab: every way to start practising, in one list. The bottom
/// navigation bar and the tab's own [Scaffold] belong to the app shell; this widget only needs
/// its own top [SafeArea] (the shell already gives it a background and handles the bottom inset).
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  // Guards a rapid double tap from pushing two intakes at once.
  bool _busy = false;

  /// Mock interview, Quick question and Practise by typing all land here: they ask for consent
  /// once, then open the intake with whichever parameters name the mode.
  Future<void> _openIntake({bool preferTyping = false, int questionCount = 5}) async {
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
        child: ValueListenableBuilder<AssistantLook>(
          valueListenable: services.assistant,
          builder: (context, look, _) => ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, Space.x4),
            children: [
              Semantics(header: true, child: Text('Practice', style: PrepType.display)),
              const SizedBox(height: Space.l),
              _FeaturedCard(look: look, onStart: _openIntake),
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      key: const ValueKey('mode-quick'),
                      look: look,
                      mood: AssistantMood.thinking,
                      title: 'Quick question',
                      meta: '1 question',
                      onTap: () => _openIntake(questionCount: 1),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: _Tile(
                      key: const ValueKey('mode-talk'),
                      look: look,
                      mood: AssistantMood.happy,
                      title: 'Talk to ${look.name}',
                      meta: 'Ask anything',
                      onTap: _openTalk,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.m),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      key: const ValueKey('mode-typing'),
                      look: look,
                      mood: AssistantMood.idle,
                      badge: PrepIcons.keyboard,
                      title: 'Type answers',
                      meta: 'No microphone',
                      onTap: () => _openIntake(preferTyping: true),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: _Tile(
                      key: const ValueKey('mode-notes'),
                      look: look,
                      mood: AssistantMood.idle,
                      badge: PrepIcons.write,
                      title: 'Your notes',
                      meta: 'Before you go in',
                      onTap: _openNotes,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xl),
              _TipCard(text: dailyTip(DateTime.now()), glow: look.tone),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mock interview, the main way to practise: the assistant asking, and a Start pill.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.look, required this.onStart});

  final AssistantLook look;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final glow = look.tone;
    return Semantics(
      button: true,
      label: 'Mock interview, 5 questions, 10 minutes',
      excludeSemantics: true,
      onTap: onStart,
      child: Material(
        color: PrepColors.surface1,
        borderRadius: BorderRadius.circular(Radii.sheet),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('mode-mock'),
          onTap: onStart,
          child: SizedBox(
            height: 196,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.7, 0.1),
                        radius: 0.9,
                        colors: [glow.withValues(alpha: 0.24), glow.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -Space.s,
                  bottom: 0,
                  child: AssistantAvatar(look: look, size: 190, mood: AssistantMood.speaking, hud: false),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mock interview', style: PrepType.titleL),
                      const SizedBox(height: Space.xxs),
                      Text('5 questions · 10 min', style: PrepType.meta),
                      const Spacer(),
                      DecoratedBox(
                        decoration: BoxDecoration(color: glow, borderRadius: BorderRadius.circular(24)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.m),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PrepIcon(PrepIcons.mic, color: PrepColors.bg, size: 18),
                              const SizedBox(width: Space.s),
                              Text('Start', style: PrepType.button.copyWith(color: PrepColors.bg)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A square-ish tile: a little assistant doing the thing, then a title and a few words.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.look,
    required this.mood,
    required this.title,
    required this.meta,
    required this.onTap,
    this.badge,
  });

  final AssistantLook look;
  final AssistantMood mood;
  final String title;
  final String meta;
  final VoidCallback onTap;
  final PrepIcons? badge;

  @override
  Widget build(BuildContext context) {
    final glow = look.tone;
    return Semantics(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 112,
                  width: double.infinity,
                  color: glow.withValues(alpha: 0.08),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: AssistantAvatar(look: look, size: 106, mood: mood, hud: false),
                      ),
                      if (badge != null)
                        Positioned(
                          left: Space.m,
                          top: Space.m,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(color: PrepColors.bg.withValues(alpha: 0.8), shape: BoxShape.circle),
                            child: Center(child: PrepIcon(badge!, color: glow, size: 16)),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: PrepType.bodyLMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Space.xxs),
                      Text(meta, style: PrepType.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// About ten practical tips, short enough to read at a glance. [dailyTip] steps through them one
/// a day, so the card is not the same on every visit but never needs its own state.
const List<String> _tips = [
  'Start with the point, then one example.',
  'Say what you did, not the team.',
  'End every story with a result.',
  'Keep each answer under two minutes.',
  'Practise out loud, not in your head.',
  'A short pause beats a filler word.',
  'Use a real number when you can.',
  'Match their energy in the room.',
  'Bring two questions to ask them.',
  'Record one answer and listen back.',
];

/// The tip for [now]'s calendar day (UTC), the same for everyone on a given day.
String dailyTip(DateTime now) => _tips[(now.toUtc().millisecondsSinceEpoch ~/ 86400000) % _tips.length];

class _TipCard extends StatelessWidget {
  const _TipCard({required this.text, required this.glow});

  final String text;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: glow.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.card)),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: PrepIcon(PrepIcons.target, color: glow, size: 20),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tip of the day', style: PrepType.label.copyWith(color: glow)),
                  const SizedBox(height: Space.xxs),
                  Text(text, style: PrepType.bodyLMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
