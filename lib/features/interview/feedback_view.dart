import 'package:flutter/material.dart';

import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';

/// Feedback on one answer, short: a headline, then at most three metal cards in the order they
/// are useful. "Good" is what worked; "Try" is their own words and the fix; "Voice" is the measured
/// pace, only for a spoken answer the phone measured. No scores.
class FeedbackView extends StatelessWidget {
  const FeedbackView({super.key, required this.feedback, required this.typed, this.metrics, this.listen});

  final AnswerFeedback feedback;

  /// Typed or corrected answers get no voice card: nothing was measured that matches the text.
  final bool typed;

  /// What the phone measured for a spoken, unedited answer.
  final DeliveryMetrics? metrics;

  /// An optional control to hear the feedback, beside the headline.
  final Widget? listen;

  @override
  Widget build(BuildContext context) {
    final headline = feedback.headline.trim();
    final problem = feedback.problem.trim();
    final evidence = _unquote(feedback.evidence);
    final fix = feedback.fix.trim();
    final strength = feedback.strength.trim();
    final measured = typed ? null : metrics;
    // The fix says what to do; the problem is only spelled out when there is no fix.
    final tryText = fix.isNotEmpty ? fix : problem;
    final title = Semantics(
      header: true,
      liveRegion: true,
      child: Text(
        headline.isEmpty ? 'One thing to work on.' : headline,
        style: PrepType.question,
        textAlign: listen == null ? TextAlign.center : TextAlign.start,
      ),
    );
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (evidence.isNotEmpty) AnswerQuote(evidence),
              if (evidence.isNotEmpty && tryText.isNotEmpty) const SizedBox(height: Space.m),
              if (tryText.isNotEmpty) Text(tryText, style: fix.isNotEmpty ? PrepType.bodyLMedium : PrepType.bodyL),
            ],
          ),
        ),
      if (measured != null && measured.wpm > 0)
        CoachCard(title: 'Voice', icon: PrepIcons.speaker, child: _Pace(measured)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listen == null)
          title
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: title), const SizedBox(width: Space.s), listen!],
          ),
        if (feedback.mock) ...[
          const SizedBox(height: Space.xs),
          Text('Sample feedback', style: PrepType.caption, textAlign: listen == null ? TextAlign.center : TextAlign.start),
        ],
        const SizedBox(height: Space.l),
        for (final (i, block) in blocks.indexed) ...[if (i > 0) const SizedBox(height: Space.m), block],
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

/// The measured pace as a big thin numeral, with a two or three word reading of it (the
/// comfortable band is 110 to 170 words a minute).
class _Pace extends StatelessWidget {
  const _Pace(this.m);

  final DeliveryMetrics m;

  @override
  Widget build(BuildContext context) {
    final wpm = m.wpm;
    final reading = wpm > 170 ? 'A bit fast' : (wpm < 110 ? 'A bit slow' : 'Easy pace');
    return Semantics(
      label: 'Pace, $wpm words a minute. $reading',
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: Space.l,
        runSpacing: Space.xs,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$wpm', style: PrepType.numeral),
              const SizedBox(width: Space.s),
              Text('words/min', style: PrepType.meta.copyWith(color: PrepColors.text3)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Text(reading, style: PrepType.titleM.copyWith(color: PrepColors.text2)),
          ),
        ],
      ),
    );
  }
}
