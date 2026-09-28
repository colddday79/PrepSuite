import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../profile/practice_history.dart';
import '../wrapup/wrapup_screen.dart';

/// Past practices on this phone. The list is the same one Profile shows. This
/// page is only the outer place to open it.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.of(context).sessions;
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.s,
                        Space.gutter,
                        Space.l,
                      ),
                      child: Text(
                        'Past practices on this phone.',
                        style: PrepType.body,
                      ),
                    ),
                    PracticeHistory(
                      sessions: sessions,
                      onOpen: (session) => _openNotes(context, session),
                      onStart: () =>
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openNotes(BuildContext context, PracticeSession session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WrapupScreen(session: session, review: true),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.xs,
          Space.s,
          Space.gutter,
          Space.s,
        ),
        child: Row(
          children: [
            IconAction(
              PrepIcons.back,
              label: 'Back',
              plain: true,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Text('History', style: PrepType.titleM),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
