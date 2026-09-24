import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../coach/coach_api.dart';
import '../../design/components.dart';
import '../../design/frosted_panel.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import '../intake/intake_screen.dart';
import '../wrapup/wrapup_screen.dart';

// Home stage geometry (ported from the native screen): the presence sits at the top and the panel
// slides over its lower edge.
const double _presenceSize = 232;
const double _panelOverlap = 72;
const double _barHeight = 64;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _askedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_askedOnce) return;
    _askedOnce = true;
    // First run: explain what happens to the person's voice before anything else.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final services = AppScope.of(context);
      if (await services.consent.accepted() || !mounted) return;
      if (await showConsentSheet(context)) await services.consent.accept();
    });
  }

  Future<void> _start({bool typing = false}) async {
    final services = AppScope.of(context);
    if (!await services.consent.accepted()) {
      if (!mounted) return;
      final ok = await showConsentSheet(context);
      if (!ok) return;
      await services.consent.accept();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => IntakeScreen(preferTyping: typing)),
    );
  }

  void _openNotes() {
    final last = AppScope.of(context).sessions.last;
    if (last == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: last, review: true)));
  }

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.of(context).sessions;
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: PresenceBackdrop(
            top: _barHeight + Space.s,
            size: _presenceSize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _barHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(left: Space.gutter, right: Space.s),
                    child: Row(
                      children: [
                        Expanded(child: Text('PrepSuite', style: PrepType.wordmark)),
                        IconAction(PrepIcons.sliders, label: 'Settings', plain: true, onPressed: () => showSettingsSheet(context)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.s + _presenceSize - _panelOverlap),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: FrostedPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text("Tell me the job. I'll ask what they will ask you.", style: PrepType.question),
                        ),
                        const SizedBox(height: Space.m),
                        Row(
                          children: [
                            const PrepIcon(PrepIcons.clock, color: PrepColors.text2, size: 18),
                            const SizedBox(width: Space.s),
                            Expanded(child: Text('Five questions, about ten minutes. Honest feedback on each.', style: PrepType.meta)),
                          ],
                        ),
                        const SizedBox(height: Space.xxl),
                        PrimaryButton('Start practice', onPressed: _start),
                        const SizedBox(height: Space.s),
                        InkWell(
                          borderRadius: BorderRadius.circular(Radii.chip),
                          onTap: () => showConsentSheet(context, infoOnly: true),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('Recordings stay on this phone.', style: PrepType.meta.copyWith(color: PrepColors.text3)),
                                ),
                                Text('Privacy', style: PrepType.label),
                              ],
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
                      title: 'Last-minute notes',
                      meta: last == null ? 'Finish a practice to keep your notes here.' : 'Your notes for ${last.jobTitle}.',
                      onTap: last == null ? null : _openNotes,
                    );
                  },
                ),
                const Hairline(indent: Space.gutter + 24 + Space.l),
                LinkRow(
                  icon: PrepIcons.keyboard,
                  title: 'Practise by typing',
                  meta: "Answer in writing when you can't talk out loud.",
                  onTap: () => _start(typing: true),
                ),
                const SizedBox(height: Space.xxl),
              ],
            ),
          ),
        ),
      ),
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
    barrierColor: const Color(0xB3000000),
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
              return _InfoRow(icon: PrepIcons.compass, title: 'Coach', lines: [status, widget.services.coachLabel]);
            },
          ),
          const Hairline(indent: Space.gutter + 24 + Space.l),
          _InfoRow(icon: PrepIcons.mic, title: 'Voice', lines: [widget.services.speechLabel]),
          const Hairline(indent: Space.gutter + 24 + Space.l),
          LinkRow(
            icon: PrepIcons.shield,
            title: 'Privacy',
            meta: 'What stays on this phone and what is sent.',
            onTap: () => showConsentSheet(context, infoOnly: true),
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
