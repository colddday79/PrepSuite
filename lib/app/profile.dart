import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How much work experience the person has, so questions and advice can be pitched sensibly.
enum ExperienceLevel {
  firstJob('First job'),
  someExperience('Some experience'),
  careerChange('Changing careers');

  const ExperienceLevel(this.label);
  final String label;
}

/// What the person chose to tell the app about themselves. Every field is optional, nothing is
/// required to start practising, and it stays on this phone.
@immutable
class Profile {
  const Profile({this.name = '', this.targetRole = '', this.interviewDate, this.experience});

  final String name;
  final String targetRole;

  /// The day of the interview (the time of day is ignored).
  final DateTime? interviewDate;
  final ExperienceLevel? experience;

  bool get isEmpty =>
      name.trim().isEmpty && targetRole.trim().isEmpty && interviewDate == null && experience == null;

  /// Calendar days from [now] to the interview: 0 on the day, negative once it has passed, null
  /// when no date is set. Counted on UTC dates so a daylight-saving change can't lose a day.
  int? daysUntilInterview(DateTime now) {
    final date = interviewDate;
    if (date == null) return null;
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(date.year, date.month, date.day);
    return day.difference(today).inDays;
  }

  Profile copyWith({
    String? name,
    String? targetRole,
    DateTime? interviewDate,
    bool clearInterviewDate = false,
    ExperienceLevel? experience,
    bool clearExperience = false,
  }) {
    return Profile(
      name: name ?? this.name,
      targetRole: targetRole ?? this.targetRole,
      interviewDate: clearInterviewDate ? null : interviewDate ?? this.interviewDate,
      experience: clearExperience ? null : experience ?? this.experience,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'target_role': targetRole,
    'interview_date': interviewDate == null
        ? null
        : '${interviewDate!.year.toString().padLeft(4, '0')}-'
              '${interviewDate!.month.toString().padLeft(2, '0')}-'
              '${interviewDate!.day.toString().padLeft(2, '0')}',
    'experience': experience?.name,
  };

  factory Profile.fromJson(Map<String, dynamic> json) {
    final raw = json['interview_date'];
    final date = raw is String ? DateTime.tryParse(raw) : null;
    final level = json['experience'];
    return Profile(
      name: json['name'] is String ? (json['name'] as String).trim() : '',
      targetRole: json['target_role'] is String ? (json['target_role'] as String).trim() : '',
      // Only the day matters, so a stored time of day (or zone) is dropped.
      interviewDate: date == null ? null : DateTime(date.year, date.month, date.day),
      experience: level is String
          ? ExperienceLevel.values.where((l) => l.name == level).firstOrNull
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.name == name &&
      other.targetRole == targetRole &&
      other.interviewDate == interviewDate &&
      other.experience == experience;

  @override
  int get hashCode => Object.hash(name, targetRole, interviewDate, experience);
}

/// Holds the [Profile], saved to this phone when [persist] is on (tests keep it in memory).
class ProfileStore extends ChangeNotifier implements ValueListenable<Profile> {
  ProfileStore({this.persist = false, Profile initial = const Profile()}) : _value = initial;

  static const _key = 'profile.v1';
  final bool persist;
  Profile _value;
  bool _restored = false;
  int _revision = 0;
  bool _disposed = false;
  bool saveFailed = false;

  @override
  Profile get value => _value;

  Future<void> restore() async {
    if (_restored || !persist) return;
    _restored = true;
    final revision = _revision;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      // A save made while preferences were opening wins over the older stored copy.
      if (raw == null || revision != _revision) return;
      _value = Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _notify();
    } catch (_) {
      // An unreadable profile must never block practising; it starts empty.
    }
  }

  Future<void> save(Profile profile) async {
    _revision++;
    _value = profile;
    saveFailed = false;
    _notify();
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      saveFailed = !await prefs.setString(_key, jsonEncode(profile.toJson()));
    } catch (_) {
      saveFailed = true;
    }
    _notify();
  }

  Future<void> clear() async {
    _revision++;
    _value = const Profile();
    saveFailed = false;
    _notify();
    if (!persist) return;
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {
      saveFailed = true;
      _notify();
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
