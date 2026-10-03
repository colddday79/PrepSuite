import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/profile.dart';
import '../../app/services.dart';
import '../../coach/coach_api.dart';
import '../../design/assistant_picker.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import 'about_me_card.dart';
import 'initial_disc.dart';
import 'profile_format.dart';

/// The Profile tab: who the person is (name, job, "About me", interview date, experience), their
/// coach, the app's look, and settings. Everything is optional, saved at once and kept on this
/// phone. A tab body: no back button, its own top [SafeArea].
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
    // Transparent: the shell's lit room shows through behind the glass.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([services.profile, services.theme]),
          builder: (context, _) {
            final profile = services.profile.value;
            final now = DateTime.now();
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, floatingTabBarInset(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(profile: profile, onEdit: () => _editNameJob(services)),
                  const SizedBox(height: Space.xxl),
                  AboutMeCard(
                    about: profile.about,
                    onEdit: () => showEditAboutSheet(context),
                    onSayIt: () => showSayItSheet(context),
                  ),
                  const _SectionHeader('Details'),
                  _Group(
                    children: [
                      LinkRow(icon: PrepIcons.user, title: 'Name', meta: profile.name, onTap: () => _editNameJob(services)),
                      LinkRow(
                        icon: PrepIcons.target,
                        title: "Job you're preparing for",
                        meta: profile.targetRole,
                        onTap: () => _editNameJob(services),
                      ),
                      _DateRow(
                        text: interviewDateLine(profile, now),
                        spoken: spokenInterviewDate(profile, now),
                        onPick: () => _pickDate(services),
                        onClear: () => services.profile.save(profile.copyWith(clearInterviewDate: true)),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
                    child: Text('Experience', style: _labelStyle),
                  ),
                  MetalSegments(
                    labels: [for (final level in ExperienceLevel.values) level.label],
                    selected: profile.experience?.index,
                    keys: [for (final level in ExperienceLevel.values) ValueKey('experience-${level.name}')],
                    selectedHint: 'clear your answer',
                    onSelect: (i) => _chooseExperience(services, ExperienceLevel.values[i]),
                  ),
                  const _SectionHeader('Your coach'),
                  ValueListenableBuilder<AssistantLook>(
                    valueListenable: services.assistant,
                    builder: (context, look, _) =>
                        AssistantPicker(selected: look.kind, onSelected: (kind) => services.assistant.choose(kind)),
                  ),
                  const _SectionHeader('Appearance'),
                  _ThemeSwatches(selected: services.theme.value, onChoose: services.theme.choose),
                  const _SectionHeader('Settings'),
                  _Group(
                    children: [
                      FutureBuilder<CoachHealth>(
                        future: _health,
                        builder: (context, snap) =>
                            LinkRow(icon: PrepIcons.compass, title: 'Connection', meta: _coachStatus(snap), onTap: null),
                      ),
                      LinkRow(
                        icon: PrepIcons.replay,
                        title: 'See the introduction again',
                        onTap: () => services.assistant.resetOnboarding(),
                      ),
                      LinkRow(
                        icon: PrepIcons.shield,
                        title: 'Privacy',
                        onTap: () => showConsentSheet(context, infoOnly: true),
                      ),
                      _DeleteRow(onTap: () => _deleteEverything(services)),
                    ],
                  ),
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

/// Matches PrepTextField's label, for the controls that aren't text fields. A getter, so it
/// follows the theme.
TextStyle get _labelStyle => PrepType.label.copyWith(color: PrepColors.text2);

/// The person's initial, their name large and the job under it, and an edit control.
class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.onEdit});

  final Profile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InitialDisc(name: profile.name, size: 56),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  profile.name.isEmpty ? 'Your profile' : profile.name,
                  style: PrepType.display,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (profile.targetRole.isNotEmpty) ...[
                const SizedBox(height: Space.xxs),
                Text(profile.targetRole, style: PrepType.meta, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        const SizedBox(width: Space.m),
        MetalDisc(PrepIcons.edit, label: 'Edit name and job', size: 48, onPressed: onEdit),
      ],
    );
  }
}

/// Rows on one metal card, with hairlines between them lined up with the titles. The ink sits
/// above the metal, so pressing a row shows.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MetalCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Hairline(indent: Space.gutter + 24 + Space.l),
              children[i],
            ],
          ],
        ),
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

/// The interview date as a row like the others: it opens the date picker, and a set date has a
/// remove control beside it.
class _DateRow extends StatelessWidget {
  const _DateRow({required this.text, required this.spoken, required this.onPick, required this.onClear});

  /// "Tue, Sep 30 · in 5 days", or null when no date is set.
  final String? text;
  final String? spoken;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final value = text;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            button: true,
            label: 'Interview date, ${spoken ?? 'not set'}',
            onTap: onPick,
            onTapHint: 'choose a date',
            excludeSemantics: true,
            child: FocusRing(
              gap: -Space.xs,
              child: InkWell(
                key: const ValueKey('profile-date'),
                onTap: onPick,
                focusColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(Space.gutter, Space.m, value == null ? Space.gutter : Space.xs, Space.m),
                    child: Row(
                      children: [
                        PrepIcon(PrepIcons.calendar, color: PrepColors.text2),
                        const SizedBox(width: Space.l),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Interview date', style: PrepType.bodyLMedium),
                              const SizedBox(height: Space.xxs),
                              Text(value ?? 'Choose a date', style: PrepType.meta.copyWith(color: PrepColors.text3)),
                            ],
                          ),
                        ),
                        if (value == null) ...[
                          const SizedBox(width: Space.m),
                          PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                        ],
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
            padding: const EdgeInsets.only(right: Space.s),
            child: IconAction(PrepIcons.close, label: 'Remove interview date', plain: true, onPressed: onClear),
          ),
      ],
    );
  }
}

/// The three themes as small metal swatches, each painted in its own metal with its accent dot.
/// The chosen one has a ring and a check. A row when they fit, a list with large text.
class _ThemeSwatches extends StatelessWidget {
  const _ThemeSwatches({required this.selected, required this.onChoose});

  final PrepThemeData selected;
  final ValueChanged<PrepThemeData> onChoose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final inRow = (box.maxWidth - 2 * Space.m) / 3 >= 92 * scale;
        final swatches = [
          for (final theme in PrepThemes.all)
            _Swatch(theme: theme, selected: theme.id == selected.id, wide: !inRow, onTap: () => onChoose(theme)),
        ];
        if (inRow) {
          return Row(
            children: [
              for (var i = 0; i < swatches.length; i++) ...[
                if (i > 0) const SizedBox(width: Space.m),
                Expanded(child: swatches[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < swatches.length; i++) ...[
              if (i > 0) const SizedBox(height: Space.s),
              swatches[i],
            ],
          ],
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme, required this.selected, required this.wide, required this.onTap});

  final PrepThemeData theme;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;

  static const double _radius = 18;

  /// Where the painted preview card sits: across the top, or down the left of a wide swatch.
  static Rect preview(Size size, bool wide) =>
      wide ? Rect.fromLTWH(8, 8, 64, size.height - 16) : Rect.fromLTWH(8, 8, size.width - 16, 46);

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
    final label = Row(
      children: [
        Expanded(child: Text(theme.name, style: PrepType.label.copyWith(color: theme.text))),
        SizedBox.square(
          dimension: 18,
          child: selected ? PrepIcon(PrepIcons.check, color: theme.accentDeep, size: 18) : null,
        ),
      ],
    );
    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${theme.name} theme',
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        radius: _radius,
        child: CustomPaint(
          painter: _SwatchPainter(theme, wide: wide),
          foregroundPainter: selected ? _SwatchRing(theme.accentDeep) : null,
          child: Material(
            type: MaterialType.transparency,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('theme-${theme.id}'),
              onTap: onTap,
              customBorder: shape,
              focusColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: wide ? 60 : 100),
                child: Padding(
                  padding: wide
                      ? const EdgeInsets.fromLTRB(84, Space.m, Space.m, Space.m)
                      : const EdgeInsets.fromLTRB(Space.m, 62, Space.m, Space.m),
                  child: wide ? Center(child: label) : Align(alignment: Alignment.bottomLeft, child: label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A swatch is a small screen in its theme: the canvas, one metal card with the accent dot and a
/// tiny accent pill on it.
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.theme, {required this.wide});

  final PrepThemeData theme;
  final bool wide;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(_Swatch._radius));
    canvas.drawRRect(outer, Paint()..color = theme.canvas);
    canvas.drawRRect(
      outer.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.hairline,
    );
    final card = _Swatch.preview(size, wide);
    final metal = RRect.fromRectAndRadius(card, const Radius.circular(12));
    canvas.drawRRect(
      metal,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.metalTop, theme.metalBottom],
        ).createShader(card),
    );
    canvas.drawRRect(
      metal.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.rimLight, theme.rimLight.withValues(alpha: 0), const Color(0x00000000), PrepColors.rimDark],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(card),
    );
    final accent = Paint()..color = theme.accent;
    canvas.drawCircle(card.topLeft + const Offset(13, 13), 5, accent);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(card.left + 9, card.bottom - 13, math.min(30, card.width - 18), 6), const Radius.circular(3)),
      accent,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.theme != theme || old.wide != wide;
}

/// The chosen swatch's ring, 1.5 dp, in its own accent.
class _SwatchRing extends CustomPainter {
  const _SwatchRing(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(_Swatch._radius)).deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SwatchRing old) => old.color != color;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.x3, Space.xs, Space.m),
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
                    child: Text(
                      'Delete everything on this phone',
                      style: PrepType.bodyLMedium.copyWith(color: PrepColors.danger),
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
