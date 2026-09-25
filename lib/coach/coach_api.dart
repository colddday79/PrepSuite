// Client for the PrepSuite coach server, plus a fake for UI work and tests.
//
// Wire contract: every call is `POST {endpoint}` with a JSON body whose
// "action" is "questions", "feedback" or "wrapup". Errors come back as
// {"error": {"code": ..., "message": ...}} with any status. Health is
// `GET {endpoint}/health`, falling back to `GET {origin}/health`.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, IOException, SocketException;

import 'package:http/http.dart' as http;

import 'contracts.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class CoachQuestion {
  final String id;
  final String text;
  final String focus;

  const CoachQuestion({
    required this.id,
    required this.text,
    required this.focus,
  });

  /// [index] is the question's position in the set; it names the question
  /// (`q1`, `q2`, ...) when the server sent no id.
  factory CoachQuestion.fromJson(Map<String, dynamic> j, int index) {
    final id = _str(j['id']);
    return CoachQuestion(
      id: id.isEmpty ? 'q${index + 1}' : id,
      text: _str(j['text']),
      focus: _str(j['focus']),
    );
  }
}

class QuestionSet {
  final String jobTitle;
  final List<CoachQuestion> questions;
  final bool mock;

  const QuestionSet({
    required this.jobTitle,
    required this.questions,
    required this.mock,
  });

  /// Drops entries that are not objects or have no text, and makes ids unique.
  factory QuestionSet.fromJson(Map<String, dynamic> j) {
    final questions = <CoachQuestion>[];
    final ids = <String>{};
    final raw = j['questions'];
    if (raw is List) {
      for (final item in raw) {
        final m = _asMap(item);
        if (m == null) continue;
        var q = CoachQuestion.fromJson(m, questions.length);
        if (q.text.isEmpty) continue;
        if (ids.contains(q.id)) {
          var n = 1;
          while (ids.contains('q$n')) {
            n++;
          }
          q = CoachQuestion(id: 'q$n', text: q.text, focus: q.focus);
        }
        ids.add(q.id);
        questions.add(q);
      }
    }
    return QuestionSet(
      jobTitle: _str(j['job_title']),
      questions: List.unmodifiable(questions),
      mock: _bool(j['mock']),
    );
  }
}

class AnswerFeedback {
  final String headline, problem, evidence, fix, delivery, strength;
  final bool mock;

  const AnswerFeedback({
    required this.headline,
    required this.problem,
    required this.evidence,
    required this.fix,
    required this.delivery,
    required this.strength,
    required this.mock,
  });

  factory AnswerFeedback.fromJson(Map<String, dynamic> j) => AnswerFeedback(
    headline: _str(j['headline']),
    problem: _str(j['problem']),
    evidence: _str(j['evidence']),
    fix: _str(j['fix']),
    delivery: _str(j['delivery']),
    strength: _str(j['strength']),
    mock: _bool(j['mock']),
  );
}

/// One answered question, sent to the wrap-up call.
class AnswerSummary {
  final String question, transcript, headline, problem, delivery;

  const AnswerSummary({
    required this.question,
    required this.transcript,
    required this.headline,
    required this.problem,
    required this.delivery,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'transcript': transcript,
    'headline': headline,
    'problem': problem,
    'delivery': delivery,
  };
}

class Wrapup {
  final List<String> tips, lastMinuteNotes, storiesToUse;
  final bool mock;

  const Wrapup({
    required this.tips,
    required this.lastMinuteNotes,
    required this.storiesToUse,
    required this.mock,
  });

  factory Wrapup.fromJson(Map<String, dynamic> j) => Wrapup(
    tips: _strList(j['tips']),
    lastMinuteNotes: _strList(j['last_minute_notes']),
    storiesToUse: _strList(j['stories_to_use']),
    mock: _bool(j['mock']),
  );
}

class CoachHealth {
  final bool ok;
  final bool mock;
  final String provider;
  final String model;
  final bool cloud;

  const CoachHealth({required this.ok, required this.mock, this.provider = '', this.model = '', this.cloud = false});
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

enum CoachErrorKind { offline, timeout, server, badResponse }

/// The only exception [CoachApi] calls throw. Show [userMessage] to people;
/// [code] and [message] are for logs (for [CoachErrorKind.server] they come
/// from the server's error body).
class CoachException implements Exception {
  final CoachErrorKind kind;
  final String code;
  final String message;

  const CoachException(this.kind, {this.code = '', this.message = ''});

  String get userMessage => switch (kind) {
    CoachErrorKind.offline => "Can't reach the coach. Check your connection and that the coach server is running, then try again.",
    CoachErrorKind.timeout =>
      'The coach is taking too long to answer. Try again in a moment.',
    CoachErrorKind.server => _serverUserMessage(message),
    CoachErrorKind.badResponse =>
      "The coach sent back something we couldn't read. Try again.",
  };

  @override
  String toString() {
    final buf = StringBuffer('CoachException(${kind.name}');
    if (code.isNotEmpty) buf.write(', $code');
    if (message.isNotEmpty) buf.write(': $message');
    buf.write(')');
    return buf.toString();
  }
}

const int _maxServerDetail = 140;

String _serverUserMessage(String raw) {
  var detail = raw
      .replaceAll('\u2014', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (detail.isEmpty) return 'The coach ran into a problem. Try again.';
  final runes = detail.runes.toList();
  if (runes.length > _maxServerDetail) {
    detail =
        '${String.fromCharCodes(runes.take(_maxServerDetail - 1)).trimRight()}\u2026';
  }
  if (!RegExp(r'[.!?\u2026]$').hasMatch(detail)) detail = '$detail.';
  return 'The coach ran into a problem: $detail Try again.';
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

abstract class CoachApi {
  /// Interview questions for [job] (the raw text the person typed or pasted).
  Future<QuestionSet> questions({required String job, int count = 5});

  /// Feedback on one answer. Pass [delivery] for spoken answers and null for
  /// typed ones.
  Future<AnswerFeedback> feedback({
    required String job,
    required String question,
    required String transcript,
    DeliveryMetrics? delivery,
  });

  /// End-of-session tips built from every answer.
  Future<Wrapup> wrapup({
    required String job,
    required List<AnswerSummary> answers,
  });

  /// Never throws: returns `ok: false` when the coach can't be reached.
  Future<CoachHealth> health();
}

class HttpCoachApi implements CoachApi {
  HttpCoachApi({
    required this.endpoint,
    http.Client? client,
    this.timeout = const Duration(seconds: 120),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// Upper bound for each health request.
  static const Duration healthTimeout = Duration(seconds: 5);

  final Uri endpoint;

  /// Per-request timeout for questions, feedback and wrapup.
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<QuestionSet> questions({required String job, int count = 5}) async {
    final json = await _post({
      'action': 'questions',
      'job': job,
      'count': count,
    });
    final set = QuestionSet.fromJson(json);
    if (set.questions.isEmpty) {
      throw const CoachException(
        CoachErrorKind.badResponse,
        code: 'no_questions',
        message: 'The response had no usable questions.',
      );
    }
    return set;
  }

  @override
  Future<AnswerFeedback> feedback({
    required String job,
    required String question,
    required String transcript,
    DeliveryMetrics? delivery,
  }) async {
    final json = await _post({
      'action': 'feedback',
      'job': job,
      'question': question,
      'transcript': transcript,
      'delivery': delivery == null ? null : _jsonSafe(delivery.toJson()),
      if (delivery == null) 'typed': true,
    });
    final fb = AnswerFeedback.fromJson(json);
    if ([fb.headline, fb.problem, fb.fix].any((t) => t.isEmpty)) {
      throw const CoachException(
        CoachErrorKind.badResponse,
        code: 'empty_feedback',
        message: 'The response was missing the main feedback or suggested fix.',
      );
    }
    return fb;
  }

  @override
  Future<Wrapup> wrapup({
    required String job,
    required List<AnswerSummary> answers,
  }) async {
    final json = await _post({
      'action': 'wrapup',
      'job': job,
      'answers': [for (final a in answers) a.toJson()],
    });
    final notes = Wrapup.fromJson(json);
    if (notes.tips.isEmpty || notes.lastMinuteNotes.isEmpty) {
      throw const CoachException(CoachErrorKind.badResponse, code: 'empty_notes', message: 'The response had no usable interview notes.');
    }
    return notes;
  }

  @override
  Future<CoachHealth> health() async {
    try {
      final wait = timeout < healthTimeout ? timeout : healthTimeout;
      final primary = endpoint.replace(
        pathSegments: [
          ...endpoint.pathSegments.where((s) => s.isNotEmpty),
          'health',
        ],
      );
      final first = await _healthAt(primary, wait);
      if (first != null) return first;
      final fallback = Uri.parse('${endpoint.origin}/health');
      if (fallback != primary) {
        final second = await _healthAt(fallback, wait);
        if (second != null) return second;
      }
    } catch (_) {
      // Health never throws; fall through to "not ok".
    }
    return const CoachHealth(ok: false, mock: false);
  }

  /// Closes the HTTP client, but only if this object created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  Future<CoachHealth?> _healthAt(Uri uri, Duration wait) async {
    try {
      final res = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(wait);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['ok'] != true) return null;
      return CoachHealth(ok: true, mock: body['mock'] == true,
        provider: _str(body['provider']), model: _str(body['model']), cloud: body['cloud'] == true);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, Object?> payload) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            endpoint,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            // Bytes, so the header stays exactly application/json (UTF-8).
            body: utf8.encode(jsonEncode(payload)),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw CoachException(
        CoachErrorKind.timeout,
        code: 'timeout',
        message: 'No answer within ${timeout.inMilliseconds} ms.',
      );
    } on http.ClientException catch (e) {
      throw CoachException(
        CoachErrorKind.offline,
        code: 'offline',
        message: e.message,
      );
    } on SocketException catch (e) {
      throw CoachException(
        CoachErrorKind.offline,
        code: 'offline',
        message: e.message,
      );
    } on HandshakeException catch (e) {
      throw CoachException(
        CoachErrorKind.offline,
        code: 'tls',
        message: e.message,
      );
    } on IOException catch (e) {
      throw CoachException(
        CoachErrorKind.offline,
        code: 'offline',
        message: '$e',
      );
    }
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final status = res.statusCode;
    Object? body;
    var parsed = false;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
      parsed = true;
    } on FormatException {
      parsed = false;
    }
    final map = parsed ? _asMap(body) : null;
    final error = map?['error'];
    if (error is Map ||
        (error is String && error.trim().isNotEmpty) ||
        error == true) {
      final e = _asMap(error);
      final code = e == null ? '' : _str(e['code']);
      throw CoachException(
        CoachErrorKind.server,
        code: code.isEmpty ? 'http_$status' : code,
        message: e == null ? _str(error) : _str(e['message']),
      );
    }
    if (status < 200 || status >= 300) {
      throw CoachException(CoachErrorKind.server, code: 'http_$status');
    }
    if (!parsed) {
      throw const CoachException(
        CoachErrorKind.badResponse,
        code: 'bad_json',
        message: 'The body was not valid JSON.',
      );
    }
    if (map == null) {
      throw const CoachException(
        CoachErrorKind.badResponse,
        code: 'bad_shape',
        message: 'The body was not a JSON object.',
      );
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

/// Canned, deterministic coach for building UI and tests without a server.
class FakeCoachApi implements CoachApi {
  FakeCoachApi({
    this.latency = const Duration(milliseconds: 600),
    this.failuresBeforeSuccess = 0,
  });

  final Duration latency;

  /// How many `questions` calls fail as offline before one succeeds.
  final int failuresBeforeSuccess;

  int _questionCalls = 0;

  @override
  Future<QuestionSet> questions({required String job, int count = 5}) async {
    _questionCalls++;
    final fail = _questionCalls <= failuresBeforeSuccess;
    await Future<void>.delayed(latency);
    if (fail) throw const CoachException(CoachErrorKind.offline);
    return QuestionSet(
      jobTitle: _jobTitleFrom(job),
      questions: List.unmodifiable(
        _fakeQuestions.take(count.clamp(1, _fakeQuestions.length)),
      ),
      mock: true,
    );
  }

  @override
  Future<AnswerFeedback> feedback({
    required String job,
    required String question,
    required String transcript,
    DeliveryMetrics? delivery,
  }) async {
    await Future<void>.delayed(latency);
    final words = transcript
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final deliveryLine = _deliveryLine(delivery);
    if (words.isEmpty) {
      return AnswerFeedback(
        headline: 'We did not get an answer.',
        problem: 'Nothing came through, so there is nothing to judge yet.',
        evidence: 'No words were recorded or typed.',
        fix: 'Try again. Talk for at least 30 seconds, or type your answer.',
        delivery: deliveryLine,
        strength: 'Nothing to praise yet. Give it a real try.',
        mock: true,
      );
    }
    // Just the words, the way the server returns an exact quote.
    final evidence = '${words.take(12).join(' ')}${words.length > 12 ? '…' : ''}';
    final saysI = RegExp(
      r'\b(i|me|my|myself)\b',
      caseSensitive: false,
    ).hasMatch(transcript);
    if (!saysI) {
      return AnswerFeedback(
        headline: 'You never said what you did.',
        problem:
            'You described the situation, not your part in it. The interviewer '
            "can't tell what you actually did.",
        evidence: evidence,
        fix: 'Say "I" and name two things you did yourself. Then say how it turned out.',
        delivery: deliveryLine,
        strength: 'You set up the situation clearly.',
        mock: true,
      );
    }
    if (words.length < 40) {
      return AnswerFeedback(
        headline: 'Too short to prove anything.',
        problem:
            'A few sentences is not enough for the interviewer to believe you.',
        evidence: evidence,
        fix:
            'Add one real example: what happened, what you did, and the result. '
            'Aim for 45 to 90 seconds.',
        delivery: deliveryLine,
        strength: 'You got to the point fast.',
        mock: true,
      );
    }
    return AnswerFeedback(
      headline: 'Good example, but no result.',
      problem: 'You explained what you did, then stopped. The interviewer never hears how it ended.',
      evidence: evidence,
      fix: 'Finish with the result. A number is best, like time saved or customers served.',
      delivery: deliveryLine,
      strength: 'You talked about your own actions, not just the team.',
      mock: true,
    );
  }

  @override
  Future<Wrapup> wrapup({
    required String job,
    required List<AnswerSummary> answers,
  }) async {
    await Future<void>.delayed(latency);
    return const Wrapup(
      tips: [
        'Start every answer with the point, then give one example.',
        'Say what you did, not what the team did.',
        'End each story with a result, even a small one.',
      ],
      lastMinuteNotes: [
        'Have one sentence ready for why you want this job.',
        'Bring two questions to ask them.',
        'Slow down on your first answer. Nerves make you rush.',
      ],
      storiesToUse: [
        'The time you learned something new fast. Use it for questions about pressure or change.',
        'The mistake you fixed. Use it for questions about weaknesses or failure.',
      ],
      mock: true,
    );
  }

  @override
  Future<CoachHealth> health() async {
    await Future<void>.delayed(latency);
    return const CoachHealth(ok: true, mock: true);
  }
}

const List<CoachQuestion> _fakeQuestions = [
  CoachQuestion(
    id: 'q1',
    text: 'Tell me about yourself.',
    focus: 'A short, relevant intro that ends on why you want this job.',
  ),
  CoachQuestion(
    id: 'q2',
    text: 'Why do you want this job?',
    focus: 'Real reasons that fit this role, not just pay or location.',
  ),
  CoachQuestion(
    id: 'q3',
    text: 'Tell me about a time you had to learn something new quickly.',
    focus: 'One real example: what you did and how you got up to speed.',
  ),
  CoachQuestion(
    id: 'q4',
    text: 'Tell me about a time you worked with someone who was hard to work with.',
    focus: 'How you handled it yourself, without blaming them.',
  ),
  CoachQuestion(
    id: 'q5',
    text: 'Tell me about a mistake you made and what you did about it.',
    focus: 'Owning it, fixing it, and what you do differently now.',
  ),
];

/// First non-empty line of the job text, capitalised, at most 60 characters.
String _jobTitleFrom(String job) {
  final line = job
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return 'Your job';
  // Spoken intake sounds like "I want a job as a junior barista at a busy cafe": keep the role.
  var title = line
      .replaceFirst(
        RegExp(r"^i\s*(?:am|'m)?\s*(?:want|would like|applying|preparing|looking|going|hoping)\b.*?\b(?:as|for|to be)\s+", caseSensitive: false),
        '',
      )
      .replaceFirst(RegExp(r'^(?:a|an|the)\s+(?:job\s+as\s+(?:a|an)\s+)?', caseSensitive: false), '');
  final cut = RegExp(r'\s+(?:at|in|with)\s+|[.,;!?]').firstMatch(title);
  if (cut != null && cut.start >= 3) title = title.substring(0, cut.start);
  if (title.trim().isEmpty) title = line;
  final runes = title.runes.toList();
  if (runes.length > 60) {
    title = String.fromCharCodes(runes.take(60));
    final space = title.lastIndexOf(' ');
    if (space >= 20) title = title.substring(0, space);
  }
  title = title.replaceAll(RegExp(r'[\s,;:\-]+$'), '');
  if (title.isEmpty) return 'Your job';
  final first = String.fromCharCode(title.runes.first);
  return first.toUpperCase() + title.substring(first.length);
}

String _deliveryLine(DeliveryMetrics? d) {
  if (d == null) return 'You typed this one, so there is no voice to judge.';
  if (d.words <= 0) return 'We could not hear any words in the recording.';
  final pace = d.wpm > 170
      ? 'fast, so slow down a little'
      : d.wpm < 110
      ? 'slow, so pick up the pace a bit'
      : 'an easy pace to follow';
  final fillers = d.fillerCount == 1
      ? '1 filler word'
      : '${d.fillerCount} filler words';
  final pause = d.longestPauseS.isFinite
      ? ' and your longest pause was ${d.longestPauseS.toStringAsFixed(1)} seconds'
      : '';
  return 'You spoke at ${d.wpm} words a minute, which is $pace. You used $fillers$pause.';
}

// ---------------------------------------------------------------------------
// Lenient JSON helpers
// ---------------------------------------------------------------------------

String _str(Object? v) => v is String ? v.trim() : '';

bool _bool(Object? v) => v == true;

List<String> _strList(Object? v) {
  if (v is! List) return const [];
  return List.unmodifiable([
    for (final e in v)
      if (e is String && e.trim().isNotEmpty) e.trim(),
  ]);
}

Map<String, dynamic>? _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key is String) e.key as String: e.value,
    };
  }
  return null;
}

/// JSON can't carry NaN or infinity; send those as null instead of crashing.
Object? _jsonSafe(Object? v) {
  if (v is double && !v.isFinite) return null;
  if (v is Map) {
    return {for (final e in v.entries) '${e.key}': _jsonSafe(e.value)};
  }
  if (v is List) return [for (final e in v) _jsonSafe(e)];
  return v;
}
