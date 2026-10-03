import 'package:flutter/material.dart';

import '../../app/session.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import 'profile_format.dart';

/// Past practices, newest first, one metal row each: the job, the date and "2/3" answered. The
/// latest opens its notes while the whole practice is still saved on the phone; older ones are
/// summaries only, so they carry no chevron.
class PracticeHistory extends StatelessWidget {
  const PracticeHistory({super.key, required this.sessions, required this.onOpen, required this.onStart});

  final SessionStore sessions;
  final ValueChanged<PracticeSession> onOpen;

  /// Takes the person to a practice.
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final records = sessions.history;
        if (records.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('No practices yet', style: PrepType.titleM),
              const SizedBox(height: Space.l),
              PrimaryButton('Practice', onPressed: onStart),
            ],
          );
        }
        final now = DateTime.now();
        final last = sessions.last;
        final latestOpens = last != null && records.first.isFor(last);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < records.length; i++) ...[
              if (i > 0) const SizedBox(height: Space.s + Space.xxs),
              _HistoryRow(
                key: ValueKey('practice-${records[i].startedAt.microsecondsSinceEpoch}'),
                record: records[i],
                now: now,
                full: i == 0 && latestOpens ? last : null,
                onOpen: onOpen,
              ),
            ],
          ],
        );
      },
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
    final notes = session != null
        ? (session.wrapup != null ? 'Notes ready' : 'Notes not written yet')
        : (record.hasNotes ? 'Notes not kept' : 'No notes');
    final onTap = session == null ? null : () => onOpen(session);
    return MetalTile(
      semanticLabel:
          '${record.jobTitle}. ${spokenDate(record.startedAt, now)}. ${record.answered} of ${record.total} answered. $notes.',
      tapHint: 'open your notes',
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.l, Space.l),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.jobTitle, style: PrepType.titleM, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xxs),
                Text(shortDate(record.startedAt, now), style: PrepType.meta),
              ],
            ),
          ),
          const SizedBox(width: Space.m),
          Text(
            '${record.answered}/${record.total}',
            style: PrepType.timer,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6),
          ),
          SizedBox(
            width: 30,
            child: onTap == null
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                  ),
          ),
        ],
      ),
    );
  }
}
