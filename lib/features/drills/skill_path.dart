import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import 'drill_content.dart';
import 'drill_progress.dart';

/// Opens a lesson from the skill path or the Home card.
typedef OpenDrillLesson = void Function(DrillSkill skill, DrillLesson lesson);

/// The four skills for the Practice tab: each a metal card with a small gauge of lessons done and
/// its title, then its lessons as rows (a check when done, an accent dot on the next one, an empty
/// ring otherwise). Every lesson is open. Not scrollable itself: it sits in the tab's own list.
class SkillPath extends StatefulWidget {
  const SkillPath({super.key, required this.progress, required this.onOpenLesson});

  final DrillProgressStore progress;
  final OpenDrillLesson onOpenLesson;

  @override
  State<SkillPath> createState() => _SkillPathState();
}

class _SkillPathState extends State<SkillPath> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.progress.restore());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.progress,
      builder: (context, _) {
        final progress = widget.progress;
        final next = progress.nextLesson();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, skill) in progress.curriculum.indexed) ...[
              if (i > 0) const SizedBox(height: Space.m),
              _SkillCard(skill: skill, progress: progress, next: next, onOpenLesson: widget.onOpenLesson),
            ],
          ],
        );
      },
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({required this.skill, required this.progress, required this.next, required this.onOpenLesson});

  final DrillSkill skill;
  final DrillProgressStore progress;
  final DrillLesson? next;
  final OpenDrillLesson onOpenLesson;

  /// Where the lesson titles start, so the hairlines between rows line up with them.
  static const double _textInset = Space.xl + _Marker.size + Space.l;

  @override
  Widget build(BuildContext context) {
    final done = progress.doneCount(skill);
    final total = skill.lessons.length;
    return MetalCard(
      key: ValueKey('skill-${skill.id}'),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        // The rows' ink lands on this layer, above the metal.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                header: true,
                label: '${skill.title}. $done of $total lessons done.',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.xl, Space.m),
                  child: Row(
                    children: [
                      ArcGauge(
                        value: total == 0 ? 0 : done / total,
                        size: 56,
                        stroke: 4,
                        child: Text('$done/$total', style: PrepType.label),
                      ),
                      const SizedBox(width: Space.l),
                      Expanded(child: Text(skill.title, style: PrepType.titleM)),
                    ],
                  ),
                ),
              ),
              for (final (i, lesson) in skill.lessons.indexed) ...[
                Hairline(indent: i == 0 ? 0 : _textInset),
                _LessonRow(
                  lesson: lesson,
                  state: progress.isDone(lesson.id)
                      ? _LessonState.done
                      : (lesson == next ? _LessonState.next : _LessonState.open),
                  onTap: () => onOpenLesson(skill, lesson),
                ),
              ],
              const SizedBox(height: Space.xs),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LessonState { done, next, open }

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, required this.state, required this.onTap});

  final DrillLesson lesson;
  final _LessonState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = '${lesson.minutes} min';
    final (String? lead, String rest) = switch (state) {
      _LessonState.done => ('Done', ''),
      _LessonState.next => ('Up next', ' · $minutes'),
      _LessonState.open => (null, minutes),
    };
    final spoken = switch (state) {
      _LessonState.done => 'Done',
      _LessonState.next => 'Up next, about ${lesson.minutes} minutes',
      _LessonState.open => 'About ${lesson.minutes} minutes',
    };
    return Semantics(
      container: true,
      button: true,
      label: '${lesson.title}. $spoken, ${lesson.exercises.length} exercises',
      excludeSemantics: true,
      onTap: onTap,
      child: FocusRing(
        radius: Radii.control,
        gap: -Space.xs,
        child: InkWell(
          key: ValueKey('skill-lesson-${lesson.id}'),
          onTap: onTap,
          focusColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.m),
              child: Row(
                children: [
                  _Marker(state: state),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lesson.title, style: PrepType.bodyLMedium),
                        const SizedBox(height: Space.xxs),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (lead != null)
                                TextSpan(
                                  text: lead,
                                  style: PrepType.meta.copyWith(
                                    color: state == _LessonState.next ? PrepColors.accentDeep : PrepColors.text2,
                                  ),
                                ),
                              if (rest.isNotEmpty) TextSpan(text: rest),
                            ],
                          ),
                          style: PrepType.meta.copyWith(color: PrepColors.text3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 28 dp mark before each lesson: a check on raised metal when done, an accent dot inside an
/// accent ring when it is next, a hairline ring otherwise.
class _Marker extends StatelessWidget {
  const _Marker({required this.state});

  static const double size = 28;

  final _LessonState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: switch (state) {
        _LessonState.done => DecoratedBox(
          decoration: BoxDecoration(
            color: PrepColors.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: PrepColors.rimLight),
          ),
          child: Center(child: PrepIcon(PrepIcons.check, color: PrepColors.text, size: 16)),
        ),
        _LessonState.next => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: PrepColors.accentDeep, width: 1.5),
          ),
          child: Center(
            child: SizedBox.square(
              dimension: 10,
              child: DecoratedBox(decoration: BoxDecoration(color: PrepColors.accent, shape: BoxShape.circle)),
            ),
          ),
        ),
        _LessonState.open => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: PrepColors.lineStrong, width: 1.5)),
          ),
        ),
      },
    );
  }
}

/// One compact metal card for Home: the next lesson on the skill path, its skill, and a thin line
/// of how far along the path is. When every lesson is done it offers to start again. Narrow enough
/// to sit in half a row.
class NextLessonCard extends StatefulWidget {
  const NextLessonCard({super.key, required this.progress, required this.onOpen});

  final DrillProgressStore progress;
  final OpenDrillLesson onOpen;

  @override
  State<NextLessonCard> createState() => _NextLessonCardState();
}

class _NextLessonCardState extends State<NextLessonCard> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.progress.restore());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.progress,
      builder: (context, _) {
        final progress = widget.progress;
        final next = progress.nextLesson();
        final allDone = next == null;
        final lesson = next ?? progress.curriculum.first.lessons.first;
        final skill = progress.skillOf(lesson);
        final count = progress.lessonCount;
        final done = progress.doneTotal;
        final title = allDone ? 'All lessons done' : lesson.title;
        final meta = allDone ? 'Start again' : skill.title;
        final gauge = ArcGauge(
          value: count == 0 ? 0 : done / count,
          size: 52,
          stroke: 4,
          child: Text('$done/$count', style: PrepType.caption.copyWith(color: PrepColors.text)),
        );
        final words = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: PrepType.titleM, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.xxs),
            Text(meta, style: PrepType.meta, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        );
        return MetalTile(
          key: const ValueKey('next-lesson-card'),
          onTap: () => widget.onOpen(skill, lesson),
          semanticLabel: allDone
              ? 'All $count skill lessons done. Start again'
              : 'Up next: ${lesson.title}, ${skill.title}. $done of $count lessons done',
          padding: const EdgeInsets.all(Space.l),
          child: LayoutBuilder(
            builder: (context, box) {
              // Half a row on Home: the gauge and the arrow share the top line, the words go under.
              if (box.maxWidth < 280) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [gauge, const Spacer(), const _ChevronDisc()]),
                    const SizedBox(height: Space.m),
                    words,
                  ],
                );
              }
              return Row(
                children: [
                  gauge,
                  const SizedBox(width: Space.l),
                  Expanded(child: words),
                  const SizedBox(width: Space.m),
                  const _ChevronDisc(),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// A small raised metal disc holding the arrow: where the card goes, drawn like the app's controls.
/// Decorative; the whole card is the button.
class _ChevronDisc extends StatelessWidget {
  const _ChevronDisc();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PrepColors.surface2, PrepColors.metalBottom],
        ),
        border: Border.all(color: PrepColors.rimLight),
      ),
      child: SizedBox.square(
        dimension: 36,
        child: Center(child: PrepIcon(PrepIcons.chevron, color: PrepColors.text2, size: 18)),
      ),
    );
  }
}
