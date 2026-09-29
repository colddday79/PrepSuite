import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../design/assistant_avatar.dart';
import '../../design/tokens.dart';
import '../profile/practice_history.dart';
import '../shell/shell_scope.dart';
import '../wrapup/wrapup_screen.dart';

/// The History tab: every past practice, newest first. A plain count line stands in for the
/// old settings-style chrome; the list itself is [PracticeHistory], shared with Profile.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  void _open(PracticeSession session) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: session, review: true)));
  }

  void _start() => ShellScope.of(context).goTo(ShellTab.practice);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([services.sessions, services.assistant]),
          builder: (context, _) {
            final history = services.sessions.history;
            final empty = history.isEmpty;
            final answers = history.fold<int>(0, (sum, r) => sum + r.answered);
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.xs),
                    child: Semantics(header: true, child: Text('History', style: PrepType.headline)),
                  ),
                  if (!empty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
                      child: Text(
                        '${history.length} ${history.length == 1 ? 'practice' : 'practices'} · '
                        '$answers ${answers == 1 ? 'answer' : 'answers'}',
                        style: PrepType.meta,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, Space.xl, 0, Space.l),
                      child: Center(
                        child: AssistantAvatar(
                          look: services.assistant.value,
                          size: 120,
                          mood: AssistantMood.idle,
                          hud: false,
                        ),
                      ),
                    ),
                  PracticeHistory(sessions: services.sessions, onOpen: _open, onStart: _start),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
