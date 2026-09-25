import '../../app/profile.dart';

// Dates written out by hand in the app's British style ("Tue 30 Sep"), so no locale package is needed.

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _daysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "Tue 30 Sep", with the year added when it isn't [now]'s year: "Fri 1 Jan 2027".
String shortDate(DateTime date, DateTime now) =>
    '${_days[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}${_year(date, now)}';

/// The same date in whole words for screen readers: "Tuesday 30 September".
String spokenDate(DateTime date, DateTime now) =>
    '${_daysLong[date.weekday - 1]} ${date.day} ${_monthsLong[date.month - 1]}${_year(date, now)}';

String _year(DateTime date, DateTime now) => date.year == now.year ? '' : ' ${date.year}';

/// "Tue 30 Sep · in 5 days" for the interview date, or null when none is set.
String? interviewDateLine(Profile profile, DateTime now) {
  final date = profile.interviewDate;
  if (date == null) return null;
  return '${shortDate(date, now)} · ${_relative(profile.daysUntilInterview(now)!)}';
}

/// The interview date as a screen reader should say it: "Tuesday 30 September, in 5 days".
String? spokenInterviewDate(Profile profile, DateTime now) {
  final date = profile.interviewDate;
  if (date == null) return null;
  return '${spokenDate(date, now)}, ${_relative(profile.daysUntilInterview(now)!)}';
}

String _relative(int days) => switch (days) {
  0 => 'today',
  1 => 'tomorrow',
  -1 => 'yesterday',
  > 1 => 'in $days days',
  _ => '${-days} days ago',
};
