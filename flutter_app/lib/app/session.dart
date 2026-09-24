import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../coach/coach_api.dart';
import '../coach/contracts.dart';

/// One answer as the coach judged it. Only the latest attempt per question is kept.
class AnswerRecord {
  const AnswerRecord({required this.transcript, required this.metrics, required this.feedback, required this.typed});

  final String transcript;
  final DeliveryMetrics? metrics;
  final AnswerFeedback feedback;
  final bool typed;
}

/// A practice run for one job. The latest completed or pending notes are saved locally.
class PracticeSession {
  PracticeSession({required this.job, required this.set, this.preferTyping = false});

  /// The job exactly as the person confirmed it, sent to the coach with every request.
  final String job;
  final QuestionSet set;
  final bool preferTyping;
  final Map<int, AnswerRecord> answers = {};
  Wrapup? wrapup;

  String get jobTitle => set.jobTitle.trim().isEmpty ? 'Your job' : set.jobTitle.trim();
  List<CoachQuestion> get questions => set.questions;

  List<AnswerSummary> summaries() {
    final order = answers.keys.toList()..sort();
    return [
      for (final i in order)
        AnswerSummary(
          question: questions[i].text,
          transcript: answers[i]!.transcript,
          headline: answers[i]!.feedback.headline,
          problem: answers[i]!.feedback.problem,
          delivery: answers[i]!.feedback.delivery,
        ),
    ];
  }
}

class SessionStore extends ChangeNotifier {
  SessionStore({this.persist = false});

  static const _key = 'interview.latest.v1';
  final bool persist;
  PracticeSession? _last;
  bool _restored = false;
  int _revision = 0;
  Future<void> _write = Future<void>.value();
  bool saveFailed = false;

  /// The most recent session, including one whose final AI request needs retrying.
  PracticeSession? get last => _last;

  Future<void> restore() async {
    if (_restored || !persist) return;
    _restored = true;
    final revision = _revision;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || revision != _revision) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final set = QuestionSet.fromJson(data['set'] as Map<String, dynamic>);
      if (set.questions.isEmpty) return;
      final session = PracticeSession(job: data['job'] as String, set: set);
      for (final item in data['answers'] as List) {
        final row = item as Map<String, dynamic>;
        final index = row['index'] as int;
        if (index < 0 || index >= set.questions.length) continue;
        session.answers[index] = AnswerRecord(
          transcript: row['transcript'] as String,
          metrics: null,
          feedback: AnswerFeedback.fromJson(row['feedback'] as Map<String, dynamic>),
          typed: row['typed'] == true,
        );
      }
      final notes = data['wrapup'];
      if (notes is Map<String, dynamic>) session.wrapup = Wrapup.fromJson(notes);
      _last = session;
      notifyListeners();
    } catch (_) {
      // A missing or incompatible saved run must not block starting a new one.
    }
  }

  Future<void> finished(PracticeSession session) async {
    _last = session;
    _revision++;
    notifyListeners();
    if (!persist) return;
    final payload = jsonEncode({
      'job': session.job,
      'set': {
        'job_title': session.set.jobTitle,
        'mock': session.set.mock,
        'questions': [for (final q in session.questions) {'id': q.id, 'text': q.text, 'focus': q.focus}],
      },
      'answers': [
        for (final entry in session.answers.entries)
          {
            'index': entry.key,
            'transcript': entry.value.transcript,
            'typed': entry.value.typed,
            'feedback': {
              'headline': entry.value.feedback.headline,
              'problem': entry.value.feedback.problem,
              'evidence': entry.value.feedback.evidence,
              'fix': entry.value.feedback.fix,
              'delivery': entry.value.feedback.delivery,
              'strength': entry.value.feedback.strength,
              'mock': entry.value.feedback.mock,
            },
          },
      ],
      'wrapup': session.wrapup == null ? null : {
        'tips': session.wrapup!.tips,
        'last_minute_notes': session.wrapup!.lastMinuteNotes,
        'stories_to_use': session.wrapup!.storiesToUse,
        'mock': session.wrapup!.mock,
      },
    });
    _write = _write.then((_) async {
      try {
        saveFailed = !await (await SharedPreferences.getInstance()).setString(_key, payload);
      } catch (_) {
        saveFailed = true;
      }
      notifyListeners();
    });
    await _write;
  }

  Future<void> clear() async {
    _revision++;
    _last = null;
    notifyListeners();
    if (persist) {
      await _write;
      await (await SharedPreferences.getInstance()).remove(_key);
    }
  }
}
