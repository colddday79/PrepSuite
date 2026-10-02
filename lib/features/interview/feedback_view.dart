import 'package:flutter/material.dart';

import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';

/// Feedback on one answer, in the order it is useful: a short verdict, what worked, the one thing
/// to improve (with their own words and the fix), and how it sounded. No scores.
class FeedbackView extends StatelessWidget {
  const FeedbackView({
    super.key,
    required this.question,
    required this.feedback,
    required this.typed,
    this.metrics,
    this.listen,
  });

  final String question;
  final AnswerFeedback feedback;

  /// Typed or corrected answers get no voice feedback: nothing was measured that matches the text.
  final bool typed;

  /// What the phone measured for a spoken, unedited answer; shown on request under "How it sounded".
  final DeliveryMetrics? metrics;

  /// The control to hear the feedback read aloud (or stop it), shown under the headline.
  final Widget? listen;

  @override
  Widget build(BuildContext context) {
    final headline = feedback.headline.trim();
    final problem = feedback.problem.trim();
    final evidence = _unquote(feedback.evidence);
    final fix = feedback.fix.trim();
    final strength = feedback.strength.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(question, style: PrepType.meta.copyWith(color: PrepColors.text3), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.s),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(headline.isEmpty ? 'Here is what to work on.' : headline, style: PrepType.titleL),
        ),
        if (feedback.mock) ...[
          const SizedBox(height: Space.xs),
          Text('Sample feedback', style: PrepType.caption),
        ],
        if (listen != null) ...[
          const SizedBox(height: Space.xs),
          // Nudged left so the icon, not the button's padding, lines up with the text.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Transform.translate(offset: const Offset(-Space.m, 0), child: listen),
          ),
          const SizedBox(height: Space.s),
        ] else
          const SizedBox(height: Space.l),
        if (strength.isNotEmpty) ...[
          CoachCard(
            title: 'What worked',
            icon: PrepIcons.check,
            iconColor: PrepColors.success,
            child: Text(strength, style: PrepType.bodyL),
          ),
          const SizedBox(height: Space.m),
        ],
        CoachCard(
          title: 'Improve this',
          icon: PrepIcons.target,
          iconColor: PrepColors.warning,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (problem.isNotEmpty) Text(problem, style: PrepType.bodyL),
              if (evidence.isNotEmpty) ...[
                if (problem.isNotEmpty) const SizedBox(height: Space.m),
                AnswerQuote(evidence),
              ],
              if (fix.isNotEmpty) ...[
                const SizedBox(height: Space.l),
                Text('Next time', style: PrepType.label.copyWith(color: PrepColors.text2)),
                const SizedBox(height: Space.xs),
                Text(fix, style: PrepType.bodyLMedium),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        CoachCard(
          title: 'How it sounded',
          icon: PrepIcons.speaker,
          child: _HowItSounded(typed: typed, delivery: feedback.delivery.trim(), metrics: typed ? null : metrics),
        ),
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
class _HowItSounded extends StatefulWidget {
  const _HowItSounded({required this.typed, required this.delivery, required this.metrics});

  final bool typed;
  final String delivery;
  final DeliveryMetrics? metrics;

  @override
  State<_HowItSounded> createState() => _HowItSoundedState();
}

class _HowItSoundedState extends State<_HowItSounded> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.typed) return Text('Typed, so no voice feedback.', style: PrepType.body);
    final metrics = widget.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.delivery.isEmpty ? 'No voice measurements came back for this answer.' : widget.delivery,
          style: PrepType.bodyL,
        ),
        if (metrics != null) ...[
          const SizedBox(height: Space.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Transform.translate(
              offset: const Offset(-Space.m, 0),
              child: QuietButton(
                _open ? 'Hide details' : 'Show details',
                icon: PrepIcons.sliders,
                onPressed: () => setState(() => _open = !_open),
              ),
            ),
          ),
          if (_open) _Measured(metrics),
        ],
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
        Text('Measured on this phone. The microphone and the room can change these numbers.', style: PrepType.caption),
      ],
    );
  }
}
