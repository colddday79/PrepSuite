import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/profile.dart';
import '../../app/services.dart';
import '../../coach/coach_api.dart';
import '../../design/components.dart';
import '../../design/frosted_panel.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import '../intake/intake_screen.dart';
import '../profile/profile_screen.dart';
import '../wrapup/wrapup_screen.dart';

const double _barHeight = 56;

/// The presence box tucks this far under the top bar; the globe's outer ring starts lower still.
const double _underBar = 16;

/// Home's presence: about half the screen. On a phone the box is a little wider than the screen,
/// so the globe fills the width and only its outer ring and the black corners run off the edges.
double homePresenceSize(Size screen, EdgeInsets padding) {
  final usable = screen.height - padding.vertical;
  return math.min(screen.width * 1.12, usable * 0.55).clamp(240.0, 640.0);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _askedOnce = false;
  bool _starting = false;
  Future<bool>? _consentRequest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_askedOnce) return;
    _askedOnce = true;
    // First run: explain what happens to the person's voice before anything else.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await _ensureConsent();
    });
  }

  Future<bool> _ensureConsent() => _consentRequest ??= _requestConsent().whenComplete(() => _consentRequest = null);

  Future<bool> _requestConsent() async {
    final services = AppScope.of(context);
    if (await services.consent.accepted()) return true;
    if (!mounted) return false;
    if (!await showConsentSheet(context)) return false;
    await services.consent.accept();
    return true;
  }

  Future<void> _start({bool typing = false}) async {
    if (_starting) return;
    _starting = true;
    try {
      if (!await _ensureConsent() || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => IntakeScreen(preferTyping: typing)),
      );
    } finally {
      _starting = false;
    }
  }

  void _openNotes() {
    final last = AppScope.of(context).sessions.last;
    if (last == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: last, review: true)));
  }

  void _openProfile() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final sessions = services.sessions;
    final media = MediaQuery.of(context);
    final presence = homePresenceSize(media.size, media.padding);
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: PresenceBackdrop(
            top: _barHeight - _underBar,
            size: presence,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _barHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(left: Space.gutter, right: Space.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(header: true, child: Text('PrepSuite', style: PrepType.wordmark)),
                        ),
                        IconAction(PrepIcons.user, label: 'Profile', plain: true, onPressed: _openProfile),
                        IconAction(PrepIcons.sliders, label: 'Settings', plain: true, onPressed: () => showSettingsSheet(context)),
                      ],
                    ),
                  ),
                ),
                KeyedSubtree(
                  key: const ValueKey('home-presence'),
                  child: SizedBox(height: presence - _underBar),
                ),
                const SizedBox(height: Space.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: FrostedPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            "Tell me the job.\nLet's practise for it.",
                            key: const ValueKey('home-headline'),
                            style: PrepType.display,
                            semanticsLabel: "Tell me the job. Let's practise for it.",
                          ),
                        ),
                        ValueListenableBuilder<Profile>(
                          valueListenable: services.profile,
                          builder: (context, profile, _) {
                            final line = interviewCountdown(profile, DateTime.now());
                            if (line == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: Space.m),
                              child: _Fact(icon: PrepIcons.calendar, text: line),
                            );
                          },
                        ),
                        const SizedBox(height: Space.xxl),
                        PrimaryButton('Start practice', key: const ValueKey('start-practice'), onPressed: _start),
                        const SizedBox(height: Space.xs),
                        FocusRing(
                          radius: Radii.chip,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Radii.chip),
                            onTap: () => showConsentSheet(context, infoOnly: true),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Center(child: Text('Privacy', style: PrepType.label.copyWith(color: PrepColors.text2))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.s),
                  child: Semantics(header: true, child: Text('More ways to prepare', style: PrepType.titleM)),
                ),
                ListenableBuilder(
                  listenable: sessions,
                  builder: (context, _) {
                    final last = sessions.last;
                    return LinkRow(
                      icon: PrepIcons.write,
                      title: last != null && last.wrapup == null ? 'Finish your interview notes' : 'Last-minute notes',
                      meta: last?.jobTitle ?? '',
                      onTap: last == null ? null : _openNotes,
                    );
                  },
                ),
                const Hairline(indent: Space.gutter + 24 + Space.l),
                LinkRow(
                  icon: PrepIcons.keyboard,
                  title: 'Practise by typing',
                  onTap: () => _start(typing: true),
                ),
                const Hairline(indent: Space.gutter + 24 + Space.l),
                LinkRow(
                  icon: PrepIcons.user,
                  title: 'Profile and history',
                  onTap: _openProfile,
                ),
                SizedBox(height: Space.xxl + media.padding.bottom),
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

/// One quiet fact line under the headline: a hairline icon and a short sentence.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final PrepIcons icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: PrepIcon(icon, color: PrepColors.text2, size: 18),
        ),
        const SizedBox(width: Space.s),
        Expanded(child: Text(text, style: PrepType.meta)),
      ],
    );
  }
}

/// A small sheet that says where the coach is and whether it answers.
Future<void> showSettingsSheet(BuildContext context) {
  final services = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: PrepColors.surface1,
    barrierColor: PrepColors.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    builder: (context) => _SettingsSheet(services: services),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.services});

  final AppServices services;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late Future<CoachHealth> _health = widget.services.coach.health();

  Future<void> _deletePractice() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete this practice?'),
      content: const Text('Your answers, notes and history will be removed.'),
      actions: [
        QuietButton('Cancel', onPressed: () => Navigator.pop(context, false)),
        QuietButton('Delete', color: PrepColors.danger, onPressed: () => Navigator.pop(context, true)),
      ],
    ));
    if (confirmed != true) return;
    await widget.services.sessions.clearAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      widget.services.sessions.saveFailed ? "Couldn't delete the saved practice. Try again." : 'Saved practice deleted.',
    )));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, Space.x3, 0, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Semantics(header: true, child: Text('Settings', style: PrepType.headline)),
          ),
          const SizedBox(height: Space.l),
          FutureBuilder<CoachHealth>(
            future: _health,
            builder: (context, snap) {
              final String status;
              if (snap.connectionState != ConnectionState.done) {
                status = 'Checking the connection';
              } else if (snap.data?.ok ?? false) {
                status = snap.data!.mock ? 'Connected. The server is giving sample answers, not real AI feedback.' : 'Connected';
              } else {
                status = 'Not reachable. Start the coach server, then check again.';
              }
              return _InfoRow(icon: PrepIcons.compass, title: 'Coach', lines: [
                status,
                if (snap.data?.provider.isNotEmpty ?? false)
                  '${snap.data!.provider} · ${snap.data!.model}${snap.data!.cloud ? ' · cloud AI' : ''}',
                widget.services.coachLabel,
              ]);
            },
          ),
          const Hairline(indent: Space.gutter + 24 + Space.l),
          _InfoRow(icon: PrepIcons.mic, title: 'Voice', lines: [widget.services.speechLabel]),
          const Hairline(indent: Space.gutter + 24 + Space.l),
          LinkRow(
            icon: PrepIcons.shield,
            title: 'Privacy',
            onTap: () => showConsentSheet(context, infoOnly: true),
          ),
          ListenableBuilder(
            listenable: widget.services.sessions,
            builder: (context, _) => widget.services.sessions.last == null && widget.services.sessions.history.isEmpty && !widget.services.sessions.saveFailed
                ? const SizedBox.shrink()
                : LinkRow(icon: PrepIcons.write, title: 'Delete saved practice',
                    onTap: _deletePractice),
          ),
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: PrimaryButton('Check again', onPressed: () => setState(() => _health = widget.services.coach.health())),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.lines});

  final PrepIcons icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrepIcon(icon, color: PrepColors.text2),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PrepType.bodyLMedium),
                for (final line in lines) Text(line, style: PrepType.meta.copyWith(color: PrepColors.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
