import 'package:flutter/material.dart';

import '../../app/session.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import 'profile_format.dart';

/// Past practices, newest first. The latest one opens its notes while the whole practice is
/// still saved on the phone; older ones are summaries only.
class PracticeHistory extends StatelessWidget {
  const PracticeHistory({super.key, required this.sessions, required this.onOpen, required this.onStart});

  final SessionStore sessions;
  final ValueChanged<PracticeSession> onOpen;

  /// Takes the person back to Home to start a practice.
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final records = sessions.history;
        if (records.isEmpty) return _Empty(onStart: onStart);
        final now = DateTime.now();
        final last = sessions.last;
        final latestOpens = last != null && records.first.isFor(last);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < records.length; i++) ...[
              if (i > 0) const Hairline(indent: Space.gutter),
              _HistoryRow(
                key: ValueKey('practice-${records[i].startedAt.microsecondsSinceEpoch}'),
                record: records[i],
                now: now,
                full: i == 0 && latestOpens ? last : null,
                onOpen: onOpen,
              ),
            ],
            if (!latestOpens || records.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
                child: Text(
                  'Only your latest practice keeps its notes.',
                  style: PrepType.meta.copyWith(color: PrepColors.text3),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your practices will be listed here once you finish one.', style: PrepType.body),
          const SizedBox(height: Space.l),
          PrimaryButton('Start practising', onPressed: onStart),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({super.key, required this.record, required this.now, required this.full, required this.onOpen});

  final PracticeRecord record;
  final DateTime now;

  /// The whole practice, when this row can open its notes.
  final PracticeSession? full;
  final ValueChanged<PracticeSession> onOpen;

  @override
  Widget build(BuildContext context) {
    final session = full;
    final answered = '${record.answered} of ${record.total} answered';
    final notes = session != null
        ? (session.wrapup != null ? 'Notes ready' : 'Notes not written yet')
        : (record.hasNotes ? 'Notes written' : 'No notes');
    final onTap = session == null ? null : () => onOpen(session);
    return Semantics(
      container: true,
      button: onTap != null,
      label: '${record.jobTitle}. ${spokenDate(record.startedAt, now)}. $answered. $notes.',
      onTap: onTap,
      onTapHint: onTap == null ? null : 'open your notes',
      excludeSemantics: true,
      child: FocusRing(
        gap: -Space.xs,
        child: InkWell(
          onTap: onTap,
          focusColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(record.jobTitle, style: PrepType.bodyLMedium),
                        const SizedBox(height: Space.xxs),
                        Text(
                          '${shortDate(record.startedAt, now)} · $answered · $notes',
                          style: PrepType.meta.copyWith(color: PrepColors.text3),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: Space.m),
                    const PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
