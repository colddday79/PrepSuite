/// Turning recogniser tokens into timed words (pure Dart).
library;

import 'types.dart';

final _hasWordChar = RegExp(r"[A-Za-z0-9]");
final _edgePunct = RegExp(r"^[^A-Za-z0-9']+|[^A-Za-z0-9']+$");

/// Merges BPE tokens (a leading space or '▁' starts a new word) into words.
///
/// [timestampsS] are token start times in seconds from the start of the
/// recogniser stream; [offsetMs] is subtracted (leading padding). End times
/// are provisional (`next word start`, at most +[maxWordMs]) until refined
/// with the audio via `DeliveryAnalyzer.refineWordEnds`.
List<TimedWord> tokensToWords(
  List<String> tokens,
  List<double> timestampsS, {
  int offsetMs = 0,
  int maxWordMs = 600,
}) {
  final texts = <String>[];
  final starts = <int>[];
  final lastTokenStarts = <int>[];
  final n = tokens.length < timestampsS.length ? tokens.length : timestampsS.length;
  var pendingSpace = false; // a bare space token starts the next word
  for (var i = 0; i < n; i++) {
    var tok = tokens[i].replaceAll('▁', ' ');
    final t = (timestampsS[i] * 1000).round() - offsetMs;
    final ms = t < 0 ? 0 : t;
    final newWord = tok.startsWith(' ') || texts.isEmpty || pendingSpace;
    tok = tok.trim();
    if (tok.isEmpty) {
      pendingSpace = true;
      continue;
    }
    pendingSpace = false;
    final isPunct = !_hasWordChar.hasMatch(tok) && tok != "'";
    if (isPunct) continue; // punctuation stays in the transcript text only
    if (newWord) {
      texts.add(tok);
      starts.add(ms);
      lastTokenStarts.add(ms);
    } else {
      texts[texts.length - 1] += tok;
      lastTokenStarts[lastTokenStarts.length - 1] = ms;
    }
  }
  final out = <TimedWord>[];
  for (var i = 0; i < texts.length; i++) {
    final text = texts[i].replaceAll(_edgePunct, '');
    if (text.isEmpty || !_hasWordChar.hasMatch(text)) continue;
    final next = i + 1 < starts.length ? starts[i + 1] : null;
    var end = lastTokenStarts[i] + 250;
    if (end > starts[i] + maxWordMs) end = starts[i] + maxWordMs;
    if (next != null && end > next) end = next;
    if (end <= starts[i]) end = starts[i] + 1;
    out.add(TimedWord(text, starts[i], end));
  }
  return out;
}

/// Lower-cases all-caps output (e.g. LibriSpeech models) and trims spaces.
String normalizeTranscriptText(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return t;
  final hasLower = RegExp(r'[a-z]').hasMatch(t);
  if (hasLower) return t;
  final lower = t.toLowerCase();
  return lower.replaceAllMapped(RegExp(r"\bi\b(?=[\s']|$)"), (_) => 'I');
}

/// Applies [normalizeTranscriptText]-style casing to a word.
String normalizeWord(String word, {required bool allCaps}) {
  if (!allCaps) return word;
  final lower = word.toLowerCase();
  if (lower == 'i' || lower.startsWith("i'")) return 'I${lower.substring(1)}';
  return lower;
}
