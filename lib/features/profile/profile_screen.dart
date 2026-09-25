import 'package:flutter/material.dart';

import '../../app/profile.dart';
import '../../app/services.dart';
import '../../app/session.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import '../wrapup/wrapup_screen.dart';
import 'practice_history.dart';
import 'profile_format.dart';

/// What the person chose to tell the app, their past practices, and their data. Everything is
/// optional, every edit is saved at once, and it all stays on this phone.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  ProfileStore? _store;

  ProfileStore get _profile => _store!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = AppScope.of(context).profile;
    if (identical(store, _store)) return;
    _store?.removeListener(_syncFields);
    _store = store..addListener(_syncFields);
    _syncFields();
  }

  /// Shows stored values that changed elsewhere (a late restore, or deleting everything)
  /// without disturbing what the person is typing.
  void _syncFields() {
    final profile = _profile.value;
    if (_name.text.trim() != profile.name) _name.text = profile.name;
    if (_role.text.trim() != profile.targetRole) _role.text = profile.targetRole;
  }

  @override
  void dispose() {
    _store?.removeListener(_syncFields);
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  void _save(Profile profile) {
    if (profile != _profile.value) _profile.save(profile);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(today.year + 2, today.month, today.day);
    final current = _profile.value.interviewDate;
    var initial = current == null ? today : DateTime(current.year, current.month, current.day);
    if (initial.isBefore(today)) initial = today;
    if (initial.isAfter(lastDay)) initial = lastDay;
    // The picker's palette comes from prepTheme(); only the toggle icons need the app's own set.
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: lastDay,
      helpText: 'Interview date',
      cancelText: 'Cancel',
      confirmText: 'Save',
      barrierColor: PrepColors.scrim,
      switchToInputEntryModeIcon: const _HairlineIcon(PrepIcons.edit),
      switchToCalendarEntryModeIcon: const _HairlineIcon(PrepIcons.calendar),
    );
    if (picked == null || !mounted) return;
    _save(_profile.value.copyWith(interviewDate: DateTime(picked.year, picked.month, picked.day)));
  }

  void _openNotes(PracticeSession session) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: session, review: true)));
  }

  void _backToPractice() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _deleteEverything() async {
    final services = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: PrepColors.scrim,
      builder: (context) => AlertDialog(
        title: const Text('Delete everything on this phone?'),
        content: const Text(
          "This deletes your details, your saved practice with its notes, and your practice history. "
          "You can't undo this.",
        ),
        actions: [
          QuietButton('Cancel', onPressed: () => Navigator.of(context).pop(false)),
          QuietButton('Delete everything', color: PrepColors.danger, onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    FocusScope.of(context).unfocus();
    await Future.wait([services.profile.clear(), services.sessions.clearAll()]);
    if (!mounted) return;
    final failed = services.profile.saveFailed || services.sessions.saveFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failed ? "Couldn't delete everything. Try again." : 'Your details and practices are deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionHeader('About you', first: true),
                    ValueListenableBuilder<Profile>(
                      valueListenable: services.profile,
                      builder: (context, profile, _) => _aboutYou(profile),
                    ),
                    const _SectionHeader('Practice history'),
                    PracticeHistory(sessions: services.sessions, onOpen: _openNotes, onStart: _backToPractice),
                    const _SectionHeader('Your data'),
                    LinkRow(
                      icon: PrepIcons.shield,
                      title: 'Privacy',
                      meta: 'What stays on this phone and what is sent.',
                      onTap: () => showConsentSheet(context, infoOnly: true),
                    ),
                    const Hairline(indent: Space.gutter + 24 + Space.l),
                    _DeleteRow(onTap: _deleteEverything),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutYou(Profile profile) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Text('Everything here is optional and stays on this phone.', style: PrepType.body),
        ),
        if (_profile.saveFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.s, Space.gutter, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                "Couldn't save that on this phone. Try the change again.",
                style: PrepType.meta.copyWith(color: PrepColors.danger),
              ),
            ),
          ),
        const SizedBox(height: Space.xl),
        _Spaced(
          // One screen-reader item: the label names the field.
          child: MergeSemantics(
            child: PrepTextField(
              fieldKey: const ValueKey('profile-name'),
              label: 'What should the coach call you?',
              controller: _name,
              hint: 'Your first name',
              maxLines: 1,
              textInputAction: TextInputAction.next,
              onChanged: (text) => _save(_profile.value.copyWith(name: text.trim())),
            ),
          ),
        ),
        _Spaced(
          child: MergeSemantics(
            child: PrepTextField(
              fieldKey: const ValueKey('profile-role'),
              label: "Job you're preparing for",
              controller: _role,
              hint: 'For example, junior barista',
              maxLines: 1,
              textInputAction: TextInputAction.done,
              onChanged: (text) => _save(_profile.value.copyWith(targetRole: text.trim())),
            ),
          ),
        ),
        _Spaced(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The control says "Interview date" itself, so the label isn't read twice.
              ExcludeSemantics(child: Text('Interview date', style: _labelStyle)),
              const SizedBox(height: Space.s),
              _DateField(
                text: interviewDateLine(profile, now),
                spoken: spokenInterviewDate(profile, now),
                onPick: _pickDate,
                onClear: () => _save(_profile.value.copyWith(clearInterviewDate: true)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
          child: Text('Experience', style: _labelStyle),
        ),
        for (final level in ExperienceLevel.values) ...[
          if (level.index > 0) const Hairline(indent: Space.gutter),
          _ChoiceRow(
            key: ValueKey('experience-${level.name}'),
            label: level.label,
            selected: profile.experience == level,
            onTap: () {
              final current = _profile.value;
              // Tapping the chosen answer again takes it back: every detail here is optional.
              _save(current.experience == level
                  ? current.copyWith(clearExperience: true)
                  : current.copyWith(experience: level));
            },
          ),
        ],
      ],
    );
  }
}

/// Matches PrepTextField's label, for the controls that aren't text fields.
final _labelStyle = PrepType.label.copyWith(color: PrepColors.text2);

/// An [Icon] that paints one of the app's hairline icons, for Material widgets such as the date
/// picker that only take an [Icon]. Colour and size come from the surrounding [IconTheme].
class _HairlineIcon extends Icon {
  const _HairlineIcon(this.glyph) : super(null);

  final PrepIcons glyph;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return PrepIcon(glyph, color: theme.color ?? PrepColors.text2, size: theme.size ?? 24);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.gutter, Space.s),
        child: Row(
          children: [
            IconAction(PrepIcons.back, label: 'Back', plain: true, onPressed: onBack),
            const SizedBox(width: Space.xs),
            Expanded(child: Semantics(header: true, child: Text('Profile', style: PrepType.titleM))),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.gutter, first ? Space.s : Space.x4, Space.gutter, Space.s),
      child: Semantics(header: true, child: Text(title, style: PrepType.titleM)),
    );
  }
}

/// One form control inside the page gutters, with the space that follows it.
class _Spaced extends StatelessWidget {
  const _Spaced({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xl), child: child);
  }
}

/// Looks like the text fields and opens the date picker. A set date can be removed.
class _DateField extends StatelessWidget {
  const _DateField({required this.text, required this.spoken, required this.onPick, required this.onClear});

  /// "Tue 30 Sep · in 5 days", or null when no date is set.
  final String? text;
  final String? spoken;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final value = text;
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Semantics(
          container: true,
          button: true,
          label: 'Interview date, ${spoken ?? 'not set'}',
          onTap: onPick,
          onTapHint: 'choose a date',
          excludeSemantics: true,
          child: FocusRing(
            child: Material(
              color: PrepColors.surface1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.control),
                side: const BorderSide(color: PrepColors.lineStrong),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('profile-date'),
                onTap: onPick,
                focusColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    // Leaves room on the right for the remove control laid over the field.
                    padding: EdgeInsets.fromLTRB(Space.l, Space.m, value == null ? Space.l : 48 + Space.xs, Space.m),
                    child: Row(
                      children: [
                        const PrepIcon(PrepIcons.calendar, color: PrepColors.text2, size: 20),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Text(
                            value ?? 'Choose a date',
                            style: PrepType.bodyL.copyWith(color: value == null ? PrepColors.text3 : PrepColors.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (value != null)
          Padding(
            padding: const EdgeInsets.only(right: Space.xs),
            child: IconAction(PrepIcons.close, label: 'Remove interview date', plain: true, onPressed: onClear),
          ),
      ],
    );
  }
}

/// One answer in a single-choice list: a plain row, with a check on the chosen one.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: label,
      onTap: onTap,
      onTapHint: selected ? 'clear your answer' : null,
      excludeSemantics: true,
      child: FocusRing(
        gap: -Space.xs,
        child: InkWell(
          onTap: onTap,
          focusColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: selected ? PrepType.bodyLMedium : PrepType.bodyL.copyWith(color: PrepColors.text2),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  SizedBox.square(
                    dimension: 22,
                    child: selected ? const PrepIcon(PrepIcons.check, color: PrepColors.accent, size: 22) : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteRow extends StatelessWidget {
  const _DeleteRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: 'Delete everything on this phone. Your details, saved practice and history.',
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        gap: -Space.xs,
        child: InkWell(
          onTap: onTap,
          focusColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
              child: Row(
                children: [
                  const PrepIcon(PrepIcons.trash, color: PrepColors.danger),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete everything on this phone',
                          style: PrepType.bodyLMedium.copyWith(color: PrepColors.danger),
                        ),
                        Text(
                          'Your details, saved practice and history.',
                          style: PrepType.meta.copyWith(color: PrepColors.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
