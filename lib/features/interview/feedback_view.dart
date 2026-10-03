import 'package:flutter/material.dart';

import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';

/// Feedback on one answer, short: a verdict, then at most three blocks in the order they are
/// useful. "Good" is what worked; "Try" is their own words and the fix; "Voice" is how it sounded,
/// shown only when the phone measured a spoken answer. No scores.
class FeedbackView extends StatelessWidget {
  const FeedbackView({super.key, required this.feedback, required this.typed, this.metrics, this.listen});

  final AnswerFeedback feedback;

  /// Typed or corrected answers get no voice block: nothing was measured that matches the text.
  final bool typed;

  /// What the phone measured for a spoken, unedited answer; the numbers are under "Details".
  final DeliveryMetrics? metrics;

  /// The small control to hear the feedback read aloud (or stop it), beside the headline.
  final Widget? listen;

  @override
  Widget build(BuildContext context) {
    final headline = feedback.headline.trim();
    final problem = feedback.problem.trim();
    final evidence = _unquote(feedback.evidence);
    final fix = feedback.fix.trim();
    final strength = feedback.strength.trim();
    final delivery = feedback.delivery.trim();
    final measured = typed ? null : metrics;
    // The fix says what to do; the problem is only spelled out when there is no fix.
    final tryText = fix.isNotEmpty ? fix : problem;
    final blocks = <Widget>[
      if (strength.isNotEmpty)
        CoachCard(
          title: 'Good',
          icon: PrepIcons.check,
          iconColor: PrepColors.success,
          child: Text(strength, style: PrepType.bodyL),
        ),
      if (evidence.isNotEmpty || tryText.isNotEmpty)
        CoachCard(
          title: 'Try',
          icon: PrepIcons.target,
          iconColor: PrepColors.warning,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fix.isEmpty && tryText.isNotEmpty) Text(tryText, style: PrepType.bodyL),
              if (evidence.isNotEmpty) ...[
                if (fix.isEmpty && tryText.isNotEmpty) const SizedBox(height: Space.m),
                AnswerQuote(evidence),
              ],
              if (fix.isNotEmpty) ...[
                if (evidence.isNotEmpty) const SizedBox(height: Space.m),
                Text(fix, style: PrepType.bodyLMedium),
              ],
            ],
          ),
        ),
      if (measured != null && delivery.isNotEmpty)
        CoachCard(title: 'Voice', icon: PrepIcons.speaker, child: _Voice(delivery: delivery, metrics: measured)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(headline.isEmpty ? 'One thing to work on.' : headline, style: PrepType.titleL),
                ),
              ),
            ),
            if (listen != null) ...[const SizedBox(width: Space.s), listen!],
          ],
        ),
        if (feedback.mock) ...[
          const SizedBox(height: Space.xs),
          Text('Sample feedback', style: PrepType.caption),
        ],
        for (final block in blocks) ...[const SizedBox(height: Space.m), block],
      ],
    );
  }

  static String _unquote(String s) {
    var t = s.trim().replaceFirst(RegExp(r'^you said:?\s*', caseSensitive: false), '');
    const quotes = ['"', '“', '”', "'"];
    while (t.isNotEmpty && quotes.contains(t[0])) {
      t = t.substring(1);
    }
    while (t.isNotEmpty && quotes.contains(t[t.length - 1])) {
      t = t.substring(0, t.length - 1);
    }
    return t.trim();
  }
}

/// One delivery observation, with the measured numbers behind it on request.
class _Voice extends StatefulWidget {
  const _Voice({required this.delivery, required this.metrics});

  final String delivery;
  final DeliveryMetrics metrics;

  @override
  State<_Voice> createState() => _VoiceState();
}

class _VoiceState extends State<_Voice> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.delivery, style: PrepType.bodyL),
        const SizedBox(height: Space.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Transform.translate(
            offset: const Offset(-Space.m, 0),
            child: QuietButton(
              _open ? 'Hide details' : 'Details',
              icon: PrepIcons.sliders,
              onPressed: () => setState(() => _open = !_open),
            ),
          ),
        ),
        if (_open) _Measured(widget.metrics),
      ],
    );
  }
}

class _Measured extends StatelessWidget {
  const _Measured(this.m);

  final DeliveryMetrics m;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Length', clock((m.durationS * 1000).round())),
      ('Pace', '${m.wpm} words a minute'),
      ('Filler words', '${m.fillerCount}'),
      if (m.longestPauseS.isFinite && m.longestPauseS > 0) ('Longest pause', '${m.longestPauseS.toStringAsFixed(1)} seconds'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (name, value) in rows) ...[
          const Hairline(),
          MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(name, style: PrepType.body)),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(value, textAlign: TextAlign.end, style: PrepType.bodyLMedium)),
                ],
              ),
            ),
          ),
        ],
        const Hairline(),
        const SizedBox(height: Space.s),
        Text('Measured on this phone. The mic and the room can change these.', style: PrepType.caption),
      ],
    );
  }
}
