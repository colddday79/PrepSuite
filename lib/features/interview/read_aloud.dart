import 'package:flutter/material.dart';

import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../design/components.dart';
import '../../design/icons.dart';

/// What Norman reads out on the interview screen besides the question itself.
enum Spoken { feedback, reply, notes }

/// Norman is shared by the question, the feedback and the coach's replies. Each read-out gets a
/// turn, so the Hear and Stop controls follow what he is actually saying, and a read-out that
/// ends late (because it was stopped or replaced) never changes the screen.
class ReadAloud extends ChangeNotifier {
  ReadAloud(this._voice);

  final InterviewerVoice _voice;
  int _turn = 0;
  Spoken? _current;
  bool _disposed = false;

  /// What Norman is reading now; null when he is quiet or reading the question.
  Spoken? get current => _current;

  /// Reads [text] aloud as [what]. Completes when he finishes, is stopped, or the voice fails.
  Future<void> say(Spoken what, String text) async {
    if (_disposed || text.trim().isEmpty) return;
    final turn = ++_turn;
    _set(what);
    try {
      await _voice.speak(text);
    } catch (_) {
      // The words stay on screen when the voice is unavailable.
    }
    if (turn == _turn) _set(null);
  }

  /// Stops Norman, whatever he is reading.
  Future<void> hush() async {
    _turn++;
    _set(null);
    try {
      await _voice.stop();
    } catch (_) {
      // Nothing is playing any more either way.
    }
  }

  void _set(Spoken? value) {
    if (_disposed || _current == value) return;
    _current = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _turn++;
    super.dispose();
  }
}

/// A quiet control to hear a piece of text read aloud, or stop it. It sits right under the text.
class ReadAloudButton extends StatelessWidget {
  const ReadAloudButton({super.key, required this.label, required this.stopLabel, required this.speaking, required this.onPressed});

  /// "Hear feedback"; [stopLabel] is what screen readers hear while it plays ("Stop reading the feedback").
  final String label;
  final String stopLabel;
  final bool speaking;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: speaking ? stopLabel : label,
      onTap: onPressed,
      excludeSemantics: true,
      child: QuietButton(speaking ? 'Stop' : label, icon: speaking ? PrepIcons.stop : PrepIcons.speaker, onPressed: onPressed),
    );
  }
}

/// The most Norman says about one answer.
const int maxSpokenFeedbackWords = 45;

/// What Norman says about an answer: the headline, then the fix, in at most
/// [maxSpokenFeedbackWords] words. The quote of what they said and the delivery numbers are for
/// reading, not listening, so they are left out.
String spokenFeedback(AnswerFeedback feedback) {
  final sentences = [
    ..._sentences(speakable(feedback.headline)),
    ..._sentences(speakable(feedback.fix)),
  ];
  final said = <String>[];
  var left = maxSpokenFeedbackWords;
  for (final sentence in sentences) {
    final words = _words(sentence).length;
    if (words <= left) {
      said.add(sentence);
      left -= words;
      continue;
    }
    // Part of a long sentence is still worth saying; a few stray words are not.
    if (left >= 6) said.add(_clip(sentence, left));
    break;
  }
  return said.join(' ');
}

/// [text] tidied for the voice: no quotation marks, dashes read as pauses, one line, and a full
/// stop at the end so Norman pauses before whatever comes next.
String speakable(String text) {
  var t = stripQuotes(text)
      .replaceAll(RegExp('["“”«»*]'), '')
      .replaceAll(RegExp(r'\s*[\u2013\u2014]\s*|\s+-\s+'), ', ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'^[\s,;:]+'), '')
      .replaceFirst(RegExp(r'[\s,;:]+$'), '');
  if (t.isEmpty) return '';
  if (!RegExp(r'[.!?…]$').hasMatch(t)) t = '$t.';
  return t;
}

final _wrapped = RegExp('^[\'"“‘«]+(.*?)[\'"”’»]+([.!?…]*)\$', dotAll: true);

/// [text] without quotation marks around the whole of it. Quotes inside it are kept.
String stripQuotes(String text) {
  final t = text.trim();
  final m = _wrapped.firstMatch(t);
  if (m == null) return t;
  final inner = m[1]!.trim();
  if (inner.isEmpty || RegExp('["“”]').hasMatch(inner)) return t;
  return '$inner${m[2]}';
}

List<String> _sentences(String text) => [
  for (final s in text.split(RegExp(r'(?<=[.!?…])\s+')))
    if (s.trim().isNotEmpty) s.trim(),
];

List<String> _words(String text) => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// The start of [sentence] in at most [budget] words, ending at a clause break when there is one
/// in the second half.
String _clip(String sentence, int budget) {
  final words = _words(sentence).take(budget).toList();
  for (var i = words.length - 1; i >= budget ~/ 2; i--) {
    if (RegExp(r'[,;:]$').hasMatch(words[i])) {
      words.removeRange(i + 1, words.length);
      break;
    }
  }
  return speakable(words.join(' '));
}
