import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
  PracticeSession({required this.job, required this.set, this.preferTyping = false, DateTime? startedAt})
      : startedAt = startedAt ?? DateTime.now();

  /// The job exactly as the person confirmed it, sent to the coach with every request.
  final String job;
  final QuestionSet set;
  final bool preferTyping;

  /// When the practice began. It tells this practice apart in the history.
  final DateTime startedAt;
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

/// A short summary of one finished practice for the history. It keeps no answers or feedback;
/// only [SessionStore.last] keeps those.
@immutable
class PracticeRecord {
  const PracticeRecord({
    required this.jobTitle,
    required this.startedAt,
    required this.finishedAt,
    required this.answered,
    required this.total,
    required this.hasNotes,
  });

  factory PracticeRecord.of(PracticeSession session, {DateTime? finishedAt}) => PracticeRecord(
    jobTitle: session.jobTitle,
    startedAt: session.startedAt,
    finishedAt: finishedAt ?? DateTime.now(),
    answered: session.answers.length,
    total: session.questions.length,
    hasNotes: session.wrapup != null,
  );

  final String jobTitle;

  /// When the practice began. Saving the same practice again updates its record.
  final DateTime startedAt;

  /// When the interview part ended (the first time the practice was saved).
  final DateTime finishedAt;
  final int answered;
  final int total;

  /// Whether interview notes were written for this practice.
  final bool hasNotes;

  bool isFor(PracticeSession session) => _sameMoment(startedAt, session.startedAt);

  Map<String, Object?> toJson() => {
    'job_title': jobTitle,
    'started_at': startedAt.toUtc().toIso8601String(),
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'answered': answered,
    'total': total,
    'has_notes': hasNotes,
  };

  /// Null when [json] can't name a practice (no start time); other fields fall back quietly.
  static PracticeRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final started = _time(json['started_at']);
    if (started == null) return null;
    final title = json['job_title'];
    final answered = _count(json['answered']);
    return PracticeRecord(
      jobTitle: title is String && title.trim().isNotEmpty ? title.trim() : 'Your job',
      startedAt: started,
      finishedAt: _time(json['finished_at']) ?? started,
      answered: answered,
      total: math.max(_count(json['total']), answered),
      hasNotes: json['has_notes'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeRecord &&
      other.jobTitle == jobTitle &&
      _sameMoment(other.startedAt, startedAt) &&
      _sameMoment(other.finishedAt, finishedAt) &&
      other.answered == answered &&
      other.total == total &&
      other.hasNotes == hasNotes;

  @override
  int get hashCode => Object.hash(
    jobTitle,
    startedAt.microsecondsSinceEpoch,
    finishedAt.microsecondsSinceEpoch,
    answered,
    total,
    hasNotes,
  );

  @override
  String toString() => 'PracticeRecord($jobTitle, $startedAt, $answered/$total, notes: $hasNotes)';
}

/// The same instant, whether the times are local or UTC.
bool _sameMoment(DateTime a, DateTime b) => a.microsecondsSinceEpoch == b.microsecondsSinceEpoch;

DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

int _count(Object? value) => value is num && value.isFinite && value > 0 ? value.toInt() : 0;

class SessionStore extends ChangeNotifier {
  SessionStore({this.persist = false});

  static const _key = 'interview.latest.v1';
  static const _historyKey = 'interview.history.v1';

  /// How many past practices [history] keeps.
  static const historyLimit = 30;

  final bool persist;
  PracticeSession? _last;
  List<PracticeRecord> _history = const [];
  bool _restored = false;
  int _revision = 0;
  int _historyResets = 0;
  Future<void> _write = Future<void>.value();
  bool _disposed = false;
  bool saveFailed = false;

  /// The most recent session, including one whose final AI request needs retrying.
  PracticeSession? get last => _last;

  /// Finished practices, newest first, at most [historyLimit]. Summaries only: the full practice
  /// (answers and notes) is kept for [last] alone.
  List<PracticeRecord> get history => _history;

  Future<void> restore() async {
    if (_restored || !persist) return;
    _restored = true;
    final revision = _revision;
    final resets = _historyResets;
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return; // Nothing saved can be read, but practising still works.
    }
    // History deleted while preferences were opening: the stored copy is on its way out.
    final stored = resets == _historyResets ? _readHistory(prefs) : const <PracticeRecord>[];
    var rewriteHistory = false;
    var rewriteLatest = false;
    if (revision == _revision) {
      final saved = _readLatest(prefs);
      if (saved != null) {
        _last = saved.session;
        // Saved by a version without start times: keep the one it has now, so later launches
        // still match it to its history row.
        rewriteLatest = !saved.dated;
      }
      _history = stored;
    } else {
      // A practice was saved or deleted while preferences were opening. That is newer than the
      // stored copy, so keep it and put the older practices back beneath it.
      final merged = _history.fold(stored, _withRecord);
      rewriteHistory = !listEquals(merged, stored);
      _history = merged;
    }
    final last = _last;
    if (last != null && !_history.any((r) => r.isFor(last))) {
      // A practice finished before the history existed starts it off.
      _history = _withRecord(_history, PracticeRecord.of(last, finishedAt: last.startedAt));
      rewriteHistory = true;
    }
    if (rewriteHistory || rewriteLatest) {
      final latest = rewriteLatest ? jsonEncode(_sessionJson(last!)) : null;
      final history = rewriteHistory ? _encodeHistory(_history) : null;
      // Housekeeping only: a failure here must not show "not saved" on a screen.
      unawaited(_queueWrite((prefs) async {
        final latestSaved = latest == null || await prefs.setString(_key, latest);
        final historySaved = history == null || await prefs.setString(_historyKey, history);
        return latestSaved && historySaved;
      }, report: false));
    }
    _notify();
  }

  ({PracticeSession session, bool dated})? _readLatest(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final set = QuestionSet.fromJson(data['set'] as Map<String, dynamic>);
      if (set.questions.isEmpty) return null;
      final startedAt = _time(data['started_at']);
      final session = PracticeSession(job: data['job'] as String, set: set, startedAt: startedAt);
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
      return (session: session, dated: startedAt != null);
    } catch (_) {
      // A missing or incompatible saved run must not block starting a new one.
      return null;
    }
  }

  List<PracticeRecord> _readHistory(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_historyKey);
      final data = raw == null ? null : jsonDecode(raw);
      if (data is! List) return const [];
      return data.map(PracticeRecord.fromJson).nonNulls.fold(const <PracticeRecord>[], _withRecord);
    } catch (_) {
      // An unreadable history starts again rather than blocking practice.
      return const [];
    }
  }

  /// [list] with [record] in it (replacing the same practice), newest first, at most
  /// [historyLimit] long.
  static List<PracticeRecord> _withRecord(List<PracticeRecord> list, PracticeRecord record) {
    final next = [
      for (final r in list)
        if (!_sameMoment(r.startedAt, record.startedAt)) r,
      record,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(next.take(historyLimit));
  }

  static String _encodeHistory(List<PracticeRecord> history) => jsonEncode([for (final r in history) r.toJson()]);

  static Map<String, Object?> _sessionJson(PracticeSession session) => {
    'job': session.job,
    'started_at': session.startedAt.toUtc().toIso8601String(),
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
  };

  /// Saves [session] as the latest practice and records it in [history]. Called when the
  /// interview ends and again when its notes arrive; both land on the same history row.
  Future<void> finished(PracticeSession session) async {
    _last = session;
    final earlier = _history.where((r) => r.isFor(session)).firstOrNull;
    _history = _withRecord(_history, PracticeRecord.of(session, finishedAt: earlier?.finishedAt));
    _revision++;
    saveFailed = false;
    _notify();
    if (!persist) return;
    final payload = jsonEncode(_sessionJson(session));
    final history = _encodeHistory(_history);
    await _queueWrite((prefs) async {
      final saved = await prefs.setString(_key, payload);
      try {
        // The history is rewritten in full on every save, so one failed write heals itself.
        await prefs.setString(_historyKey, history);
      } catch (_) {}
      // Only the practice itself decides "not saved": the notes are what the person needs.
      return saved;
    });
  }

  /// Save and delete operations share one queue so deleting old notes cannot
  /// erase a newer session that finishes while preferences are being opened.
  Future<void> _queueWrite(Future<bool> Function(SharedPreferences) action, {bool report = true}) {
    final revision = _revision;
    _write = _write.then((_) async {
      bool failed;
      try {
        failed = !await action(await SharedPreferences.getInstance());
      } catch (_) {
        failed = true;
      }
      if (report && revision == _revision) {
        saveFailed = failed;
        _notify();
      }
    });
    return _write;
  }

  /// Deletes the saved practice (its answers, feedback and notes). The history keeps its summary.
  Future<void> clear() async {
    _revision++;
    _last = null;
    saveFailed = false;
    _notify();
    if (persist) {
      await _queueWrite((prefs) => prefs.remove(_key));
    }
  }

  /// Deletes the saved practice and the whole history, for "delete everything".
  Future<void> clearAll() async {
    _revision++;
    _historyResets++;
    _last = null;
    _history = const [];
    saveFailed = false;
    _notify();
    if (persist) {
      await _queueWrite((prefs) async {
        final latest = await prefs.remove(_key);
        final history = await prefs.remove(_historyKey);
        return latest && history;
      });
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
