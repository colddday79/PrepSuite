import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import 'drill_content.dart';
import 'drill_parts.dart';
import 'drill_progress.dart';

/// Opens a lesson from the skill path or the Home card.
typedef OpenDrillLesson = void Function(DrillSkill skill, DrillLesson lesson);

/// The four skills as a calm list for the Practice tab: each skill a card with its title, one
/// line about it, how many lessons are done and a thin track, then its lessons as rows. Every
/// lesson is open; the first unfinished one is marked "Up next". Not scrollable itself: it sits in
/// the tab's own list.
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
    return Material(
      key: ValueKey('skill-${skill.id}'),
      color: PrepColors.surface1,
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            label: '${skill.title}. ${skill.summary} $done of $total lessons done.',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(skill.title, style: PrepType.titleM)),
                      const SizedBox(width: Space.m),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('$done of $total lessons', style: PrepType.meta),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(skill.summary, style: PrepType.body),
                  const SizedBox(height: Space.l),
                  ThinTrack(value: total == 0 ? 0 : done / total),
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
        ],
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
    final count = '${lesson.exercises.length} exercises';
    final (String? lead, String rest) = switch (state) {
      _LessonState.done => ('Done', ' · $count'),
      _LessonState.next => ('Up next', ' · $count · about ${lesson.minutes} min'),
      _LessonState.open => (null, '$count · about ${lesson.minutes} min'),
    };
    final leadColor = state == _LessonState.next ? PrepColors.accent : PrepColors.text2;
    return Semantics(
      container: true,
      button: true,
      label: '${lesson.title}. ${lead ?? ''}${lead == null ? rest : rest.replaceAll(' · ', ', ')}',
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
                                TextSpan(text: lead, style: PrepType.meta.copyWith(color: leadColor)),
                              TextSpan(text: rest),
                            ],
                          ),
                          style: PrepType.meta.copyWith(color: PrepColors.text3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  const PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 28 dp ring before each lesson: a check when done, a filled centre when it is next.
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
          decoration: BoxDecoration(color: PrepColors.accentTint, shape: BoxShape.circle),
          child: Center(child: PrepIcon(PrepIcons.check, color: PrepColors.accent, size: 18)),
        ),
        _LessonState.next => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: PrepColors.accent, width: 2),
          ),
          child: Center(
            child: SizedBox.square(
              dimension: 10,
              child: DecoratedBox(decoration: BoxDecoration(color: PrepColors.accent, shape: BoxShape.circle)),
            ),
          ),
        ),
        _LessonState.open => const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: PrepColors.lineStrong, width: 1.5)),
          ),
        ),
      },
    );
  }
}

/// One compact card for Home: the next lesson on the skill path, its skill, and how far along the
/// path is. When every lesson is done it says so and offers to practice again from the start.
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
        final label = allDone ? 'Skill practice' : 'Up next';
        final title = allDone ? 'All $count lessons done' : lesson.title;
        final meta = allDone ? 'Practice again from the start' : '${skill.title} · about ${lesson.minutes} min';
        void open() => widget.onOpen(skill, lesson);
        return Semantics(
          container: true,
          button: true,
          label: allDone
              ? 'All $count skill lessons done. Practice again from the start'
              : 'Up next: ${lesson.title}, ${skill.title}. $done of $count lessons done',
          excludeSemantics: true,
          onTap: open,
          child: FocusRing(
            radius: Radii.card,
            child: Material(
              key: const ValueKey('next-lesson-card'),
              color: PrepColors.surface1,
              borderRadius: BorderRadius.circular(Radii.card),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.card),
                onTap: open,
                focusColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: PrepColors.accentTint, shape: BoxShape.circle),
                            child: Center(
                              child: PrepIcon(
                                allDone ? PrepIcons.replay : PrepIcons.write,
                                color: PrepColors.accent,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.l),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label, style: PrepType.label.copyWith(color: PrepColors.text2)),
                                const SizedBox(height: Space.xxs),
                                Text(title, style: PrepType.titleM),
                                const SizedBox(height: Space.xxs),
                                Text(meta, style: PrepType.meta),
                              ],
                            ),
                          ),
                          const SizedBox(width: Space.m),
                          const PrepIcon(PrepIcons.chevron, color: PrepColors.text3, size: 18),
                        ],
                      ),
                      const SizedBox(height: Space.l),
                      Row(
                        children: [
                          Expanded(child: ThinTrack(value: count == 0 ? 0 : done / count)),
                          const SizedBox(width: Space.m),
                          // Flexible so very large text wraps instead of pushing past the edge.
                          Flexible(child: Text('$done of $count lessons', style: PrepType.meta, textAlign: TextAlign.end)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
