import 'package:flutter/material.dart';

import '../../coach/coach_api.dart';
import '../../design/tokens.dart';

/// Feedback on one answer: a blunt headline, what went wrong, the words that show it, the fix,
/// how it sounded, and what worked. Short and scannable, no scores.
class FeedbackView extends StatelessWidget {
  const FeedbackView({super.key, required this.question, required this.feedback, required this.typed});

  final String question;
  final AnswerFeedback feedback;
  final bool typed;

  @override
  Widget build(BuildContext context) {
    final evidence = feedback.evidence.trim();
    final delivery = feedback.delivery.trim();
    final strength = feedback.strength.trim();
    final fix = feedback.fix.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (feedback.mock) ...[
          Text('Sample feedback', style: PrepType.label.copyWith(color: PrepColors.accent)),
          const SizedBox(height: Space.s),
        ],
        Text(question, style: PrepType.meta.copyWith(color: PrepColors.text3), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.m),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(feedback.headline.trim().isEmpty ? 'Here is what to fix.' : feedback.headline.trim(), style: PrepType.headline),
        ),
        if (feedback.problem.trim().isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text(feedback.problem.trim(), style: PrepType.bodyL),
        ],
        if (evidence.isNotEmpty)
          _Section(
            label: 'What you said',
            child: Text('“${_unquote(evidence)}”', style: PrepType.quote.copyWith(color: PrepColors.text2)),
          ),
        if (fix.isNotEmpty) _Section(label: 'Fix it', child: Text(fix, style: PrepType.bodyL)),
        if (delivery.isNotEmpty || typed)
          _Section(
            label: typed ? 'Voice delivery not assessed' : 'How it sounded',
            child: Text(typed ? 'This answer was typed or edited. Voice delivery was not assessed.' : delivery, style: PrepType.body),
          ),
        if (strength.isNotEmpty) _Section(label: 'What worked', child: Text(strength, style: PrepType.body)),
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
    return t;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 1, child: ColoredBox(color: PrepColors.line)),
          const SizedBox(height: Space.l),
          Text(label, style: PrepType.label.copyWith(color: PrepColors.text2)),
          const SizedBox(height: Space.xs),
          child,
        ],
      ),
    );
  }
}
