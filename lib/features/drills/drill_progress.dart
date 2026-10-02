import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drill_content.dart';

/// A finished lesson's best result: how many scored exercises were right on the first try.
@immutable
class DrillScore {
  const DrillScore(this.correct, this.total);

  final int correct;
  final int total;

  /// Higher first-try share wins; a tie keeps the existing record.
  bool beats(DrillScore other) => correct * other.total > other.correct * total;
}

/// Which skill-path lessons are done, with the best first-try score of each. Saved on this phone
/// under [storageKey] when [persist] is on; tests keep it in memory.
///
/// The app shares one [instance]. Call [restore] once at start-up (it is safe to call again; the
/// skill path widgets call it too).
class DrillProgressStore extends ChangeNotifier {
  DrillProgressStore({this.persist = false, this.curriculum = drillCurriculum}) : _restored = !persist;

  static const storageKey = 'drills.progress.v1';

  static DrillProgressStore? _instance;

  /// The app-wide store, saved on this phone.
  static DrillProgressStore get instance => _instance ??= DrillProgressStore(persist: true);

  final bool persist;
  final List<DrillSkill> curriculum;
  final Map<String, DrillScore> _best = {};
  bool _restored;
  bool _restoring = false;
  bool _disposed = false;

  /// Saved progress has been read.
  bool get restored => _restored;

  bool isDone(String lessonId) => _best.containsKey(lessonId);

  /// The best first-try result for [lessonId], or null when it has not been finished.
  DrillScore? best(String lessonId) => _best[lessonId];

  /// How many of [skill]'s lessons are done.
  int doneCount(DrillSkill skill) => skill.lessons.where((l) => isDone(l.id)).length;

  int get lessonCount => curriculum.fold(0, (n, s) => n + s.lessons.length);

  /// Lessons in the curriculum that are done (saved ids from older content are ignored).
  int get doneTotal => curriculum.fold(0, (n, s) => n + doneCount(s));

  bool get allDone => doneTotal == lessonCount;

  /// The first unfinished lesson in path order, or null when every lesson is done.
  DrillLesson? nextLesson() {
    for (final skill in curriculum) {
      for (final lesson in skill.lessons) {
        if (!isDone(lesson.id)) return lesson;
      }
    }
    return null;
  }

  /// The skill [lesson] belongs to.
  DrillSkill skillOf(DrillLesson lesson) => curriculum.firstWhere((s) => s.lessons.contains(lesson));

  Future<void> restore() async {
    if (_restored || _restoring) return;
    _restoring = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(storageKey);
      if (raw != null) {
        // A lesson finished while this was loading keeps its better score.
        _decode(raw).forEach((id, score) {
          final current = _best[id];
          if (current == null || score.beats(current)) _best[id] = score;
        });
      }
    } catch (_) {
      // Unreadable preferences: start with nothing done.
    }
    _restored = true;
    _restoring = false;
    _notify();
  }

  /// Records a finished lesson: [correct] of [total] scored exercises right on the first try.
  Future<void> complete(String lessonId, int correct, int total) async {
    final safeTotal = total < 0 ? 0 : total;
    final score = DrillScore(correct.clamp(0, safeTotal), safeTotal);
    final current = _best[lessonId];
    if (current == null || score.beats(current)) _best[lessonId] = score;
    _notify();
    await _save();
  }

  /// Forgets every lesson (Settings, "Delete everything").
  Future<void> clear() async {
    _best.clear();
    _notify();
    if (!persist) return;
    try {
      await (await SharedPreferences.getInstance()).remove(storageKey);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!persist) return;
    try {
      final lessons = {
        for (final e in _best.entries) e.key: {'correct': e.value.correct, 'total': e.value.total},
      };
      await (await SharedPreferences.getInstance()).setString(storageKey, jsonEncode({'lessons': lessons}));
    } catch (_) {
      // Worst case the lesson shows as not done next launch.
    }
  }

  /// Reads `{"lessons": {"intro-1": {"correct": 4, "total": 5}}}`, skipping anything malformed.
  static Map<String, DrillScore> _decode(String raw) {
    final out = <String, DrillScore>{};
    final Object? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return out;
    }
    if (data is! Map) return out;
    final lessons = data['lessons'];
    if (lessons is! Map) return out;
    lessons.forEach((id, value) {
      if (id is! String || value is! Map) return;
      final correct = value['correct'];
      final total = value['total'];
      if (correct is! int || total is! int || total < 0 || correct < 0 || correct > total) return;
      out[id] = DrillScore(correct, total);
    });
    return out;
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
