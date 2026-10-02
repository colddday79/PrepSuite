import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/profile.dart';
import '../../app/services.dart';
import '../../coach/coach_api.dart';
import '../../design/assistant_avatar.dart';
import '../../design/assistant_picker.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import 'about_me_card.dart';
import 'profile_format.dart';

/// The Profile tab: the chosen assistant and the person's name, the "About me" card at its
/// centre, their details, their assistant, and account-level settings. Everything here is
/// optional and saved at once; it stays on this phone. This is a tab body (the app shell owns
/// navigation), so there is no back button and it keeps its own top [SafeArea].
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<CoachHealth>? _health;

  Future<void> _editNameJob(AppServices services) async {
    final profile = services.profile.value;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PrepColors.surface1,
      barrierColor: PrepColors.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _NameJobSheet(initialName: profile.name, initialJob: profile.targetRole),
      ),
    );
    if (result != null) {
      final p = services.profile;
      p.save(p.value.copyWith(name: result.$1, targetRole: result.$2));
    }
  }

  Future<void> _pickDate(AppServices services) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(today.year + 2, today.month, today.day);
    final current = services.profile.value.interviewDate;
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
    final p = services.profile;
    p.save(p.value.copyWith(interviewDate: DateTime(picked.year, picked.month, picked.day)));
  }

  void _chooseExperience(AppServices services, ExperienceLevel level) {
    final current = services.profile.value;
    // Tapping the chosen answer again takes it back: every detail here is optional.
    services.profile.save(
      current.experience == level ? current.copyWith(clearExperience: true) : current.copyWith(experience: level),
    );
  }

  Future<void> _deleteEverything(AppServices services) async {
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
    await Future.wait([services.profile.clear(), services.sessions.clearAll(), services.drills.clear()]);
    if (!mounted) return;
    final failed = services.profile.saveFailed || services.sessions.saveFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failed ? "Couldn't delete everything. Try again." : 'Your details and practices are deleted.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    _health ??= services.coach.health();
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: ValueListenableBuilder<Profile>(
          valueListenable: services.profile,
          builder: (context, profile, _) {
            final now = DateTime.now();
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Space.l),
                  _Header(profile: profile, onEdit: () => _editNameJob(services)),
                  const SizedBox(height: Space.xxl),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: AboutMeCard(
                      about: profile.about,
                      onEdit: () => showEditAboutSheet(context),
                      onSayIt: () => showSayItSheet(context),
                    ),
                  ),
                  const _SectionHeader('Details'),
                  LinkRow(icon: PrepIcons.user, title: 'Name', meta: profile.name, onTap: () => _editNameJob(services)),
                  const Hairline(indent: Space.gutter + 24 + Space.l),
                  LinkRow(
                    icon: PrepIcons.target,
                    title: "Job you're preparing for",
                    meta: profile.targetRole,
                    onTap: () => _editNameJob(services),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The control says "Interview date" itself, so the label isn't read twice.
                        ExcludeSemantics(child: Text('Interview date', style: _labelStyle)),
                        const SizedBox(height: Space.s),
                        _DateField(
                          text: interviewDateLine(profile, now),
                          spoken: spokenInterviewDate(profile, now),
                          onPick: () => _pickDate(services),
                          onClear: () => services.profile.save(profile.copyWith(clearInterviewDate: true)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xs),
                    child: Text('Experience', style: _labelStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: _ExperienceControl(
                      selected: profile.experience,
                      onSelected: (level) => _chooseExperience(services, level),
                    ),
                  ),
                  const _SectionHeader('Your assistant'),
                  ValueListenableBuilder<AssistantLook>(
                    valueListenable: services.assistant,
                    builder: (context, look, _) =>
                        AssistantPicker(selected: look.kind, onSelected: (kind) => services.assistant.choose(kind)),
                  ),
                  const _SectionHeader('Settings'),
                  FutureBuilder<CoachHealth>(
                    future: _health,
                    builder: (context, snap) =>
                        LinkRow(icon: PrepIcons.compass, title: 'Coach', meta: _coachStatus(snap), onTap: null),
                  ),
                  const Hairline(indent: Space.gutter + 24 + Space.l),
                  LinkRow(
                    icon: PrepIcons.replay,
                    title: 'See the introduction again',
                    onTap: () => services.assistant.resetOnboarding(),
                  ),
                  const Hairline(indent: Space.gutter + 24 + Space.l),
                  LinkRow(
                    icon: PrepIcons.shield,
                    title: 'Privacy',
                    onTap: () => showConsentSheet(context, infoOnly: true),
                  ),
                  const Hairline(indent: Space.gutter + 24 + Space.l),
                  _DeleteRow(onTap: () => _deleteEverything(services)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _coachStatus(AsyncSnapshot<CoachHealth> snap) {
  if (snap.connectionState != ConnectionState.done) return 'Checking';
  final health = snap.data;
  if (health == null || !health.ok) return 'Not reachable';
  return health.mock ? 'Sample answers' : 'Connected';
}

/// Matches PrepTextField's label, for the controls that aren't text fields.
final _labelStyle = PrepType.label.copyWith(color: PrepColors.text2);

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.onEdit});

  final Profile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ValueListenableBuilder<AssistantLook>(
            valueListenable: services.assistant,
            builder: (context, look, _) => AssistantAvatar(look: look, size: 72, hud: false, animate: false),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(profile.name.isEmpty ? 'Your profile' : profile.name, style: PrepType.display),
                ),
                if (profile.targetRole.isNotEmpty) ...[
                  const SizedBox(height: Space.xxs),
                  Text(profile.targetRole, style: PrepType.body),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.s),
          IconAction(PrepIcons.edit, label: 'Edit name and job', plain: true, onPressed: onEdit),
        ],
      ),
    );
  }
}

/// Owns its own controllers so they are disposed only once this sheet itself leaves the tree
/// (after its closing animation), never by the caller that awaited it.
class _NameJobSheet extends StatefulWidget {
  const _NameJobSheet({required this.initialName, required this.initialJob});

  final String initialName;
  final String initialJob;

  @override
  State<_NameJobSheet> createState() => _NameJobSheetState();
}

class _NameJobSheetState extends State<_NameJobSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _job = TextEditingController(text: widget.initialJob);

  @override
  void dispose() {
    _name.dispose();
    _job.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop((_name.text.trim(), _job.text.trim()));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xxl, Space.x3, Space.xxl, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(header: true, child: Text('Name and job', style: PrepType.headline)),
          const SizedBox(height: Space.xxl),
          PrepTextField(
            fieldKey: const ValueKey('profile-name'),
            label: 'Name',
            controller: _name,
            hint: 'Your name',
            maxLines: 1,
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: Space.xl),
          PrepTextField(
            fieldKey: const ValueKey('profile-role'),
            label: "Job you're preparing for",
            controller: _job,
            hint: 'For example, junior barista',
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.xl),
          PrimaryButton('Save', onPressed: _save),
        ],
      ),
    );
  }
}

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

/// First job / some experience / changing careers, as one control. Tapping the chosen segment
/// again clears it: every detail here is optional.
class _ExperienceControl extends StatelessWidget {
  const _ExperienceControl({required this.selected, required this.onSelected});

  final ExperienceLevel? selected;
  final ValueChanged<ExperienceLevel> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PrepColors.surface1,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: PrepColors.lineStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.xs),
        child: Row(
          children: [
            for (final level in ExperienceLevel.values)
              Expanded(
                child: _Segment(level: level, selected: selected == level, onTap: () => onSelected(level)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.level, required this.selected, required this.onTap});

  final ExperienceLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: level.label,
      onTap: onTap,
      onTapHint: selected ? 'clear your answer' : null,
      excludeSemantics: true,
      child: FocusRing(
        radius: Radii.chip,
        gap: -Space.xs,
        child: Material(
          color: selected ? PrepColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.chip),
          animationDuration: Motion.fade,
          child: InkWell(
            key: ValueKey('experience-${level.name}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.chip),
            focusColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
                child: Center(
                  child: Text(
                    level.label,
                    textAlign: TextAlign.center,
                    style: selected
                        ? PrepType.label.copyWith(color: PrepColors.text)
                        : PrepType.label.copyWith(color: PrepColors.text2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.s),
      child: Semantics(header: true, child: Text(title, style: PrepType.titleM)),
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
