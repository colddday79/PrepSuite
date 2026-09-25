import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prepsuite/coach/coach_api.dart';
import 'package:prepsuite/coach/contracts.dart';

final Uri endpoint = Uri.parse('http://coach.test/coach');

const DeliveryMetrics metrics = DeliveryMetrics(
  durationS: 42.5,
  words: 110,
  wpm: 155,
  pausesOver1s: 3,
  longestPauseS: 2.4,
  fillerCount: 4,
  fillers: {'um': 3, 'like': 1},
  loudnessDbMean: -23.1,
  loudnessDbSd: 4.2,
  trailingOff: false,
  pitchHzMean: null,
  pitchSemitoneSd: null,
  monotone: null,
  speechRatio: 0.82,
);

const Map<String, Object?> questionsBody = {
  'job_title': 'Barista',
  'questions': [
    {'id': 'q1', 'text': 'Tell me about yourself.', 'focus': 'Short intro'},
    {'id': 'q2', 'text': 'Why this cafe?', 'focus': 'Motivation'},
  ],
  'mock': true,
};

const Map<String, Object?> feedbackBody = {
  'headline': 'You never said what you did.',
  'problem': 'All team, no you.',
  'evidence': 'You said: "we fixed it"',
  'fix': 'Say "I".',
  'delivery': 'Good pace.',
  'strength': 'Clear setup.',
  'mock': false,
};

http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json'},
    );

/// An API whose client records each request and answers with [reply].
({HttpCoachApi api, List<http.Request> requests}) harness(
  FutureOr<http.Response> Function(http.Request request) reply, {
  Duration timeout = const Duration(seconds: 60),
}) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return reply(request);
  });
  return (
    api: HttpCoachApi(endpoint: endpoint, client: client, timeout: timeout),
    requests: requests,
  );
}

Map<String, dynamic> bodyOf(http.Request r) =>
    jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

Future<CoachException> caught(Future<Object?> call) async {
  try {
    await call;
  } on CoachException catch (e) {
    return e;
  }
  fail('Expected a CoachException');
}

class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  group('requests', () {
    test('questions posts the raw job text and count as JSON', () async {
      final h = harness((_) => jsonResponse(questionsBody));
      await h.api.questions(job: '  Barista at a busy cafe\n', count: 3);
      final r = h.requests.single;
      expect(r.method, 'POST');
      expect(r.url, endpoint);
      expect(r.headers['content-type'], 'application/json');
      expect(bodyOf(r), {
        'action': 'questions',
        'job': '  Barista at a busy cafe\n',
        'count': 3,
      });
    });

    test('questions defaults count to 5', () async {
      final h = harness((_) => jsonResponse(questionsBody));
      await h.api.questions(job: 'Barista');
      expect(bodyOf(h.requests.single)['count'], 5);
    });

    test(
      'spoken feedback sends the delivery object and no typed flag',
      () async {
        final h = harness((_) => jsonResponse(feedbackBody));
        await h.api.feedback(
          job: 'Barista',
          question: 'Why us?',
          transcript: 'I love coffee.',
          delivery: metrics,
        );
        final body = bodyOf(h.requests.single);
        expect(body['action'], 'feedback');
        expect(body['job'], 'Barista');
        expect(body['question'], 'Why us?');
        expect(body['transcript'], 'I love coffee.');
        expect(body.containsKey('typed'), isFalse);
        final d = body['delivery'] as Map<String, dynamic>;
        expect(d.keys, unorderedEquals(metrics.toJson().keys));
        expect(d['pauses_over_1s'], 3);
        expect(d['longest_pause_s'], 2.4);
        expect(d['filler_count'], 4);
        expect(d['fillers'], {'um': 3, 'like': 1});
        expect(d['wpm'], 155);
        expect(d['speech_ratio'], 0.82);
        expect(d.containsKey('pitch_hz_mean'), isTrue);
        expect(d['pitch_hz_mean'], isNull);
      },
    );

    test('typed feedback sends delivery null and typed true', () async {
      final h = harness((_) => jsonResponse(feedbackBody));
      await h.api.feedback(
        job: 'Barista',
        question: 'Why us?',
        transcript: 'Typed answer',
      );
      final body = bodyOf(h.requests.single);
      expect(body.containsKey('delivery'), isTrue);
      expect(body['delivery'], isNull);
      expect(body['typed'], isTrue);
    });

    test('non-finite delivery numbers are sent as null', () async {
      final h = harness((_) => jsonResponse(feedbackBody));
      const odd = DeliveryMetrics(
        durationS: 3,
        words: 0,
        wpm: 0,
        pausesOver1s: 0,
        longestPauseS: double.nan,
        fillerCount: 0,
        fillers: {},
        loudnessDbMean: double.negativeInfinity,
        loudnessDbSd: 0,
        trailingOff: true,
        pitchHzMean: null,
        pitchSemitoneSd: null,
        monotone: null,
        speechRatio: 0,
      );
      await h.api.feedback(
        job: 'x',
        question: 'q',
        transcript: '',
        delivery: odd,
      );
      final d = bodyOf(h.requests.single)['delivery'] as Map<String, dynamic>;
      expect(d['longest_pause_s'], isNull);
      expect(d['loudness_db_mean'], isNull);
      expect(d['duration_s'], 3);
    });

    test('wrapup sends every answer summary', () async {
      final h = harness(
        (_) => jsonResponse({
          'tips': ['One'],
          'last_minute_notes': ['Breathe'],
          'stories_to_use': [],
        }),
      );
      await h.api.wrapup(
        job: 'Barista',
        answers: const [
          AnswerSummary(
            question: 'Q1',
            transcript: 'T1',
            headline: 'H1',
            problem: 'P1',
            delivery: 'D1',
          ),
          AnswerSummary(
            question: 'Q2',
            transcript: 'T2',
            headline: 'H2',
            problem: 'P2',
            delivery: 'D2',
          ),
        ],
      );
      expect(bodyOf(h.requests.single), {
        'action': 'wrapup',
        'job': 'Barista',
        'answers': [
          {
            'question': 'Q1',
            'transcript': 'T1',
            'headline': 'H1',
            'problem': 'P1',
            'delivery': 'D1',
          },
          {
            'question': 'Q2',
            'transcript': 'T2',
            'headline': 'H2',
            'problem': 'P2',
            'delivery': 'D2',
          },
        ],
      });
    });
  });

  group('parsing', () {
    test('questions happy path', () async {
      final set = await harness((_) => jsonResponse(questionsBody)).api
          .questions(job: 'Barista');
      expect(set.jobTitle, 'Barista');
      expect(set.mock, isTrue);
      expect(set.questions.map((q) => q.id), ['q1', 'q2']);
      expect(set.questions.first.text, 'Tell me about yourself.');
      expect(set.questions.first.focus, 'Short intro');
    });

    test('questions are parsed leniently', () async {
      final h = harness(
        (_) => jsonResponse({
          'job_title': 42,
          'mock': 'yes',
          'questions': [
            {'text': '  First question  ', 'focus': 7},
            'not a question',
            {'id': 'x', 'text': '   '},
            {'id': 9, 'text': 'Second question', 'focus': ' Focus '},
            {'id': 'q1', 'text': 'Duplicate id'},
            null,
          ],
        }),
      );
      final set = await h.api.questions(job: 'x');
      expect(set.jobTitle, '');
      expect(set.mock, isFalse);
      expect(set.questions.map((q) => q.id), ['q1', 'q2', 'q3']);
      expect(set.questions.map((q) => q.text), [
        'First question',
        'Second question',
        'Duplicate id',
      ]);
      expect(set.questions.map((q) => q.focus), ['', 'Focus', '']);
      expect(CoachQuestion.fromJson(const {}, 4).id, 'q5');
    });

    test('no usable questions is a bad response', () async {
      for (final body in [
        {'job_title': 'X', 'questions': []},
        {
          'job_title': 'X',
          'questions': [
            {'id': 'q1', 'text': ''},
            'nope',
          ],
        },
        {'job_title': 'X'},
        {'job_title': 'X', 'questions': 'Tell me about yourself.'},
      ]) {
        final e = await caught(
          harness((_) => jsonResponse(body)).api.questions(job: 'x'),
        );
        expect(e.kind, CoachErrorKind.badResponse, reason: '$body');
      }
    });

    test('feedback happy path and lenient fields', () async {
      final fb = await harness((_) => jsonResponse(feedbackBody)).api
          .feedback(job: 'x', question: 'q', transcript: 't');
      expect(fb.headline, 'You never said what you did.');
      expect(fb.evidence, 'You said: "we fixed it"');
      expect(fb.strength, 'Clear setup.');
      expect(fb.mock, isFalse);

      final lenient = AnswerFeedback.fromJson(const {
        'headline': '  Too long.  ',
        'problem': 3,
        'evidence': null,
        'fix': ['a'],
        'mock': 'true',
      });
      expect(lenient.headline, 'Too long.');
      expect([
        lenient.problem,
        lenient.evidence,
        lenient.fix,
        lenient.delivery,
        lenient.strength,
      ], everyElement(''));
      expect(lenient.mock, isFalse);
    });

    test('feedback with no text at all is a bad response', () async {
      final e = await caught(
        harness((_) => jsonResponse({'mock': true})).api
            .feedback(job: 'x', question: 'q', transcript: 't'),
      );
      expect(e.kind, CoachErrorKind.badResponse);
    });

    test('wrapup happy path and lenient lists', () async {
      final w = await harness(
        (_) => jsonResponse({
          'tips': ['  One  ', '', 3, null, 'Two'],
          'last_minute_notes': [' Breathe ', false],
          'stories_to_use': ['Story'],
          'mock': true,
        }),
      ).api.wrapup(job: 'x', answers: const []);
      expect(w.tips, ['One', 'Two']);
      expect(w.lastMinuteNotes, ['Breathe']);
      expect(w.storiesToUse, ['Story']);
      expect(w.mock, isTrue);

      // Notes with no usable tips or reminders are a bad response, not an empty screen.
      await expectLater(
        harness((_) => jsonResponse({'tips': ['One'], 'last_minute_notes': 'not a list'})).api.wrapup(job: 'x', answers: const []),
        throwsA(isA<CoachException>().having((e) => e.code, 'code', 'empty_notes')),
      );

      final empty = Wrapup.fromJson(const {});
      expect([
        empty.tips,
        empty.lastMinuteNotes,
        empty.storiesToUse,
      ], everyElement(isEmpty));
      expect(empty.mock, isFalse);
    });

    test('bodies are decoded as UTF-8 both ways', () async {
      final h = harness(
        (_) => http.Response.bytes(
          utf8.encode(
            '{"job_title":"Café barista","questions":[{"text":"Why our café?","focus":"naïve"}]}',
          ),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );
      final set = await h.api.questions(job: 'Café barista');
      expect(set.jobTitle, 'Café barista');
      expect(set.questions.single.text, 'Why our café?');
      expect(set.questions.single.focus, 'naïve');
      expect(bodyOf(h.requests.single)['job'], 'Café barista');
    });
  });

  group('errors', () {
    test(
      '4xx and 5xx error bodies are server errors with code and message',
      () async {
        for (final status in [400, 429, 500, 503]) {
          final h = harness(
            (_) => jsonResponse({
              'error': {'code': 'rate_limited', 'message': 'Slow down a bit.'},
            }, status),
          );
          final e = await caught(h.api.questions(job: 'x'));
          expect(e.kind, CoachErrorKind.server);
          expect(e.code, 'rate_limited');
          expect(e.message, 'Slow down a bit.');
          expect(
            e.userMessage,
            'The coach ran into a problem: Slow down a bit. Try again.',
          );
        }
      },
    );

    test('non-2xx without an error body uses http_<status>', () async {
      final h = harness((_) => http.Response('<html>Bad gateway</html>', 502));
      final e = await caught(
        h.api.feedback(job: 'x', question: 'q', transcript: 't'),
      );
      expect(e.kind, CoachErrorKind.server);
      expect(e.code, 'http_502');
      expect(e.message, '');
      expect(e.userMessage, 'The coach ran into a problem. Try again.');
    });

    test('a 200 body that contains an error is still an error', () async {
      final h = harness(
        (_) => jsonResponse({
          'error': {'message': 'Model is overloaded'},
        }),
      );
      final e = await caught(h.api.wrapup(job: 'x', answers: const []));
      expect(e.kind, CoachErrorKind.server);
      expect(e.code, 'http_200');
      expect(e.message, 'Model is overloaded');
      expect(
        e.userMessage,
        'The coach ran into a problem: Model is overloaded. Try again.',
      );

      final plain = await caught(
        harness((_) => jsonResponse({'error': 'Bad key'}, 401)).api
            .questions(job: 'x'),
      );
      expect(plain.code, 'http_401');
      expect(plain.message, 'Bad key');
    });

    test('invalid JSON or a non-object body is a bad response', () async {
      for (final body in ['not json', '[1, 2]', '"text"', '']) {
        final e = await caught(
          harness((_) => http.Response(body, 200)).api.questions(job: 'x'),
        );
        expect(e.kind, CoachErrorKind.badResponse, reason: body);
      }
      final bad = await caught(
        harness((_) => http.Response.bytes([0x7b, 0xff, 0x7d], 200)).api
            .questions(job: 'x'),
      );
      expect(bad.kind, CoachErrorKind.badResponse);
    });

    test('connection failures are offline', () async {
      final failures = <Object>[
        http.ClientException('Connection refused'),
        const SocketException('No route to host'),
        const HandshakeException('Bad certificate'),
      ];
      for (final failure in failures) {
        final e = await caught(
          harness((_) => throw failure).api.questions(job: 'x'),
        );
        expect(e.kind, CoachErrorKind.offline, reason: '$failure');
        expect(
          e.userMessage,
          "Can't reach the coach. Check your connection and that the coach server is running, then try again.",
        );
      }
    });

    test('a slow coach times out', () async {
      final h = harness((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return jsonResponse(questionsBody);
      }, timeout: const Duration(milliseconds: 20));
      final e = await caught(h.api.questions(job: 'x'));
      expect(e.kind, CoachErrorKind.timeout);
      expect(
        e.userMessage,
        'The coach is taking too long to answer. Try again in a moment.',
      );
    });

    test(
      'user messages are short and plain, and long server messages are trimmed',
      () {
        for (final kind in CoachErrorKind.values) {
          final m = CoachException(kind).userMessage;
          expect(m, isNot(contains('\u2014')));
          expect(m.length, lessThan(120));
        }
        expect(
          const CoachException(CoachErrorKind.badResponse).userMessage,
          "The coach sent back something we couldn't read. Try again.",
        );

        final long = CoachException(
          CoachErrorKind.server,
          message: 'a' * 400,
        ).userMessage;
        expect(long, startsWith('The coach ran into a problem: aaa'));
        expect(long, endsWith('\u2026 Try again.'));
        expect(
          long.length,
          'The coach ran into a problem: '.length + 140 + ' Try again.'.length,
        );

        const dashed = CoachException(
          CoachErrorKind.server,
          message: 'Model busy \u2014 retry\nsoon',
        );
        expect(
          dashed.userMessage,
          'The coach ran into a problem: Model busy - retry soon. Try again.',
        );
        expect(dashed.toString(), contains('server'));
      },
    );

    test('close leaves an injected client open', () {
      final client = _TrackingClient();
      HttpCoachApi(endpoint: endpoint, client: client).close();
      expect(client.closed, isFalse);
    });
  });

  group('health', () {
    test('uses {endpoint}/health when it answers', () async {
      final h = harness((_) => jsonResponse({'ok': true, 'mock': true}));
      final health = await h.api.health();
      expect(health.ok, isTrue);
      expect(health.mock, isTrue);
      expect(h.requests.single.method, 'GET');
      expect(
        h.requests.single.url.toString(),
        'http://coach.test/coach/health',
      );
    });

    test('falls back to {origin}/health', () async {
      final h = harness(
        (r) => r.url.path == '/health'
            ? jsonResponse({'ok': true, 'mock': false})
            : http.Response('Not found', 404),
      );
      final health = await h.api.health();
      expect(health.ok, isTrue);
      expect(health.mock, isFalse);
      expect(h.requests.map((r) => r.url.toString()), [
        'http://coach.test/coach/health',
        'http://coach.test/health',
      ]);
    });

    test('never throws and reports not ok when both fail', () async {
      final h = harness(
        (r) => r.url.path == '/health'
            ? http.Response('<html>oops</html>', 500)
            : throw http.ClientException('Connection refused'),
      );
      final health = await h.api.health();
      expect(health.ok, isFalse);
      expect(health.mock, isFalse);
      expect(h.requests, hasLength(2));
    });

    test('a hanging health check gives up and reports not ok', () async {
      final h = harness((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return jsonResponse({'ok': true, 'mock': false});
      }, timeout: const Duration(milliseconds: 20));
      expect((await h.api.health()).ok, isFalse);
    });

    test('an endpoint at the root is only tried once', () async {
      final requests = <http.Request>[];
      final api = HttpCoachApi(
        endpoint: Uri.parse('http://coach.test'),
        client: MockClient((r) async {
          requests.add(r);
          return http.Response('nope', 404);
        }),
      );
      expect((await api.health()).ok, isFalse);
      expect(requests.single.url.toString(), 'http://coach.test/health');
    });
  });

  group('FakeCoachApi', () {
    test(
      'fails the first failuresBeforeSuccess question calls, then succeeds',
      () async {
        final api = FakeCoachApi(
          latency: Duration.zero,
          failuresBeforeSuccess: 2,
        );
        for (var i = 0; i < 2; i++) {
          final e = await caught(api.questions(job: 'barista'));
          expect(e.kind, CoachErrorKind.offline);
        }
        final set = await api.questions(
          job: '  barista   at a busy cafe \nWe are hiring now',
        );
        expect(set.jobTitle, 'Barista');
        expect(
          (await api.questions(job: 'I want a job as a junior barista at a busy coffee shop in the city.')).jobTitle,
          'Junior barista',
        );
        expect(set.mock, isTrue);
        expect(set.questions, hasLength(5));
        expect(set.questions.map((q) => q.id).toSet(), hasLength(5));
        expect(
          set.questions.every((q) => q.text.isNotEmpty && q.focus.isNotEmpty),
          isTrue,
        );

        expect((await api.questions(job: '   ')).jobTitle, 'Your job');
        final long = await api.questions(
          job: 'junior software developer at a small company that builds tools for farmers',
        );
        expect(long.jobTitle.length, lessThanOrEqualTo(60));
        expect(long.jobTitle, startsWith('Junior software developer'));
      },
    );

    test(
      'feedback quotes the transcript and reads the delivery numbers',
      () async {
        final api = FakeCoachApi(latency: Duration.zero);
        final words = List.generate(20, (i) => 'w$i').join(' ');
        final spoken = await api.feedback(
          job: 'x',
          question: 'q',
          transcript: 'We $words',
          delivery: metrics,
        );
        expect(spoken.headline, 'You never said what you did.');
        expect(spoken.evidence, contains('We w0 w1'));
        expect(spoken.evidence, contains('w10'));
        expect(spoken.evidence, isNot(contains('w11')));
        expect(spoken.delivery, contains('155 words a minute'));
        expect(spoken.delivery, contains('4 filler words'));
        expect(spoken.delivery, contains('2.4 seconds'));
        expect(spoken.mock, isTrue);

        final typed = await api.feedback(
          job: 'x',
          question: 'q',
          transcript: 'I served 200 customers a day.',
        );
        expect(
          typed.delivery,
          'You typed this one, so there is no voice to judge.',
        );
        expect(typed.headline, isNotEmpty);
      },
    );

    test(
      'wrapup has 3 tips, 3 notes and 2 stories; health is ok and mock',
      () async {
        final api = FakeCoachApi(latency: Duration.zero);
        final w = await api.wrapup(job: 'x', answers: const []);
        expect(w.tips, hasLength(3));
        expect(w.lastMinuteNotes, hasLength(3));
        expect(w.storiesToUse, hasLength(2));
        expect(w.mock, isTrue);
        final health = await api.health();
        expect(health.ok, isTrue);
        expect(health.mock, isTrue);
      },
    );

    test('fake copy has no em dashes', () async {
      final api = FakeCoachApi(latency: Duration.zero);
      final set = await api.questions(job: 'Barista');
      final w = await api.wrapup(job: 'x', answers: const []);
      final copy = <String>[
        for (final q in set.questions) ...[q.text, q.focus],
        ...w.tips,
        ...w.lastMinuteNotes,
        ...w.storiesToUse,
      ];
      for (final transcript in [
        '',
        'We did it.',
        'I did it.',
        List.filled(50, 'I did it').join(' '),
      ]) {
        final fb = await api.feedback(
          job: 'x',
          question: 'q',
          transcript: transcript,
          delivery: metrics,
        );
        copy.addAll([
          fb.headline,
          fb.problem,
          fb.evidence,
          fb.fix,
          fb.delivery,
          fb.strength,
        ]);
        expect(fb.headline, isNotEmpty);
      }
      expect(copy.where((s) => s.contains('\u2014')), isEmpty);
    });
  });
}
