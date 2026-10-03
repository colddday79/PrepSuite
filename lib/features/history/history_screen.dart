import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import '../profile/practice_history.dart';
import '../shell/shell_scope.dart';
import '../wrapup/wrapup_screen.dart';

/// The History tab: every past practice, newest first, as metal rows. Empty, the coach waits on
/// the page with one way to Practice.
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
    final title = Semantics(
      header: true,
      child: Text(
        'History',
        style: PrepType.display,
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6),
      ),
    );
    final padding = EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, floatingTabBarInset(context));
    // Transparent: the shell's lit room shows through behind the glass.
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([services.sessions, services.assistant]),
        builder: (context, _) {
          if (services.sessions.history.isEmpty) {
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: padding,
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        const Spacer(),
                        LayoutBuilder(
                          builder: (context, box) => Center(
                            child: AssistantAvatar(
                              look: services.assistant.value,
                              size: math.min(box.maxWidth * 0.62, 240),
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.l),
                        Text('No practices yet', style: PrepType.titleM, textAlign: TextAlign.center),
                        const SizedBox(height: Space.xl),
                        PrimaryButton('Practice', onPressed: _start),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: padding,
            children: [
              title,
              const SizedBox(height: Space.xxl),
              PracticeHistory(sessions: services.sessions, onOpen: _open, onStart: _start),
            ],
          );
        },
      ),
    );
  }
}
