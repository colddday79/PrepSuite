/// Filler-word counting from a transcript (pure Dart).
///
/// Counts depend on the recogniser writing fillers down; the bundled Kroko
/// model usually keeps "um" but can drop a quick "uh". Ambiguous words are
/// counted conservatively:
/// * `like` only next to a comma, at the start of a sentence, or beside
///   another filler ("I was like, wow" counts; "I'd like to" does not).
/// * `you know` only when followed by punctuation, the end, or a filler.
/// * `sort of` / `kind of` not after a determiner ("what kind of job").
/// * `I mean` not before it/that/to/what.
/// * `basically`, `actually` always count.
library;

const _um = {'um', 'umm', 'ummm', 'uhm', 'uhmm', 'hm', 'hmm', 'hmmm'};
const _uh = {'uh', 'uhh', 'uhhh', 'ah', 'ahh'};
const _er = {'er', 'err', 'erm', 'errm'};
const _always = {'basically', 'actually'};
const _hesitations = {..._um, ..._uh, ..._er};
const _determiners = {
  'what', 'which', 'this', 'that', 'the', 'a', 'an', 'any', 'some', 'every',
  'each', 'one', 'same', 'different', 'other', 'another', 'these', 'those',
  'all', 'no', 'my', 'your', 'our', 'their', 'his', 'her', 'its', 'right',
  'first', 'only', 'best', 'certain', 'particular', 'new', 'many', 'several',
  'what\'s', 'whatever',
};
const _youKnowLiteral = {
  'do', 'did', 'don\'t', 'didn\'t', 'if', 'as', 'what', 'whatever', 'that',
  'everything', 'all', 'would', 'will', 'you\'ll', 'let',
};
const _iMeanLiteral = {'it', 'that', 'to', 'what', 'this', 'exactly'};

class _Tok {
  final String t; // lowercase word, or punctuation mark
  final bool punct;
  const _Tok(this.t, this.punct);
}

List<_Tok> _tokenize(String text) {
  final norm = text.replaceAll('’', "'").replaceAll('‘', "'").toLowerCase();
  return [
    for (final m in RegExp(r"[a-z0-9]+(?:'[a-z]+)*|[.,!?;:—-]").allMatches(norm))
      _Tok(m.group(0)!, !RegExp(r'[a-z0-9]').hasMatch(m.group(0)!)),
  ];
}

String _canon(String w) {
  if (_um.contains(w)) return 'um';
  if (_uh.contains(w)) return 'uh';
  if (_er.contains(w)) return 'er';
  return w;
}

/// Returns counts per canonical filler (only non-zero entries).
Map<String, int> countFillers(String text) {
  final toks = _tokenize(text);
  final out = <String, int>{};
  void add(String k) => out[k] = (out[k] ?? 0) + 1;

  _Tok? at(int i) => (i >= 0 && i < toks.length) ? toks[i] : null;
  bool isBoundary(_Tok? t) => t == null || t.punct; // start/end or punctuation
  bool isHesitation(_Tok? t) => t != null && !t.punct && _hesitations.contains(t.t);

  for (var i = 0; i < toks.length; i++) {
    final tok = toks[i];
    if (tok.punct) continue;
    final w = tok.t;
    final prev = at(i - 1), next = at(i + 1);

    if (_hesitations.contains(w)) {
      add(_canon(w));
    } else if (_always.contains(w)) {
      add(w);
    } else if (w == 'like') {
      final filler = prev == null ||
          prev.punct ||
          (next != null && next.punct && next.t == ',') ||
          isHesitation(prev) ||
          isHesitation(next) ||
          prev.t == 'like' ||
          (next != null && !next.punct && next.t == 'like' && isBoundary(at(i + 2)));
      if (filler) add('like');
    } else if (w == 'you' && next != null && !next.punct && next.t == 'know') {
      final after = at(i + 2);
      final literal = prev != null && !prev.punct && _youKnowLiteral.contains(prev.t);
      if (!literal && (isBoundary(after) || isHesitation(after))) {
        add('you know');
        i++;
      }
    } else if ((w == 'sort' || w == 'kind') && next != null && next.t == 'of') {
      final literal = prev != null && !prev.punct && _determiners.contains(prev.t);
      if (!literal) {
        add('$w of');
        i++;
      }
    } else if (w == 'i' && next != null && next.t == 'mean') {
      final after = at(i + 2);
      final literal = after != null && !after.punct && _iMeanLiteral.contains(after.t);
      if (!literal) {
        add('i mean');
        i++;
      }
    }
  }
  return out;
}

/// Number of words in [text] (letters/digits with inner apostrophes).
int countWords(String text) => _tokenize(text).where((t) => !t.punct).length;
