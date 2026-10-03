import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../app/assistant.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/glass.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/practice_chrome.dart';
import '../../design/robot_stage.dart';
import '../../design/tokens.dart';
import 'drill_content.dart';
import 'drill_parts.dart';
import 'drill_progress.dart';

/// Opens [lesson] as a full-screen step sequence.
Future<void> openDrillLesson(
  BuildContext context, {
  required DrillSkill skill,
  required DrillLesson lesson,
  required AssistantLook look,
  required DrillProgressStore progress,
  VoidCallback? onPracticeAloud,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DrillLessonScreen(
        lesson: lesson,
        skill: skill,
        look: look,
        progress: progress,
        onPracticeAloud: onPracticeAloud,
      ),
    ),
  );
}

/// One lesson of the skill path: a short run of exercises answered by tapping metal tiles (and
/// one written rewrite), each checked straight away. The bottom bar becomes a result card with one
/// reason. A miss comes back once at the end; the score counts first tries. The finished lesson is
/// saved to [progress].
///
/// [onPracticeAloud], when set, adds "Practice aloud" to the finish screen. The lesson route is
/// closed first, then the callback runs.
class DrillLessonScreen extends StatefulWidget {
  const DrillLessonScreen({
    super.key,
    required this.lesson,
    required this.skill,
    required this.look,
    required this.progress,
    this.onPracticeAloud,
  });

  final DrillLesson lesson;
  final DrillSkill skill;
  final AssistantLook look;
  final DrillProgressStore progress;
  final VoidCallback? onPracticeAloud;

  @override
  State<DrillLessonScreen> createState() => _DrillLessonScreenState();
}

class _DrillLessonScreenState extends State<DrillLessonScreen> {
  late final List<DrillExercise> _queue = List.of(widget.lesson.exercises);
  final _missed = <String>{};
  final _text = TextEditingController();
  final _scroll = ScrollController();

  /// On the right answer after a miss, and on the model rewrite, so either can be scrolled into
  /// view.
  final _revealKey = GlobalKey();

  /// The robot beside the prompt.
  static const double _robot = 96;

  int _index = 0;

  /// Exercises finished for good: right, or a second try either way.
  int _resolved = 0;

  /// The chosen tile (choice, odd one out) or bank word (fill in the blank).
  int? _pick;

  /// For ordering: which part sits in each step, as an index into the right order.
  List<int?> _slots = const [];
  bool _checked = false;
  bool _right = false;
  bool _done = false;
  bool _closing = false;

  DrillLesson get _lesson => widget.lesson;
  DrillExercise get _current => _queue[_index];
  bool get _isRetry => _index >= _lesson.exercises.length;
  bool get _started => _index > 0 || _checked || _pick != null || _slots.any((s) => s != null) || _text.text.trim().isNotEmpty;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _reset();
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onText() {
    if (!_checked && _current is RewriteExercise) setState(() {});
  }

  void _reset() {
    final exercise = _current;
    _pick = null;
    _slots = exercise is OrderExercise ? List<int?>.filled(exercise.steps.length, null) : const [];
    _text.clear();
    _checked = false;
    _right = false;
  }

  bool get _canCheck => switch (_current) {
    ChoiceExercise() || OddOneOutExercise() || FillBlankExercise() => _pick != null,
    OrderExercise() => _slots.every((s) => s != null),
    RewriteExercise() => drillWordCount(_text.text) >= RewriteExercise.minWords,
  };

  void _check() {
    if (_checked || !_canCheck) return;
    final exercise = _current;
    final right = switch (exercise) {
      ChoiceExercise e => _pick == e.answer,
      OddOneOutExercise e => _pick == e.answer,
      FillBlankExercise e => _pick == e.answerIndex,
      OrderExercise _ => _slots.indexed.every((slot) => slot.$2 == slot.$1),
      RewriteExercise _ => true,
    };
    FocusScope.of(context).unfocus();
    setState(() {
      _checked = true;
      _right = right;
      if (!right && !_isRetry) {
        // First miss: it comes back once at the end, and it no longer counts as right first time.
        _missed.add(exercise.id);
        _queue.add(exercise);
      } else {
        _resolved++;
      }
    });
    if (right && exercise.scored) HapticFeedback.selectionClick();
    // Bring the marked answer (or the model rewrite) into view once the result card has grown.
    if (!right || exercise is RewriteExercise) {
      final index = _index;
      void reveal() {
        if (mounted && _checked && _index == index) _reveal(_revealKey);
      }

      if (_still) {
        WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
      } else {
        Future<void>.delayed(Motion.enter, reveal);
      }
    }
  }

  /// Scrolls the least distance that shows all of [key]'s box (or its top, if it is taller than
  /// the view).
  void _reveal(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box == null || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _scroll.position;
    final atTop = viewport.getOffsetToReveal(box, 0).offset;
    final atBottom = viewport.getOffsetToReveal(box, 1).offset;
    var target = position.pixels;
    if (target > atTop) {
      target = atTop;
    } else if (target < atBottom) {
      target = math.min(atBottom, atTop);
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    if (_still) {
      position.jumpTo(target);
    } else {
      position.animateTo(target, duration: Motion.enter, curve: Motion.standard);
    }
  }

  void _continue() {
    if (!_checked) return;
    if (_index + 1 >= _queue.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _reset();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _finish() {
    final total = _lesson.scoredCount;
    setState(() => _done = true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(widget.progress.complete(_lesson.id, total - _missed.length, total));
  }

  Future<void> _close() async {
    if (_closing) return;
    if (_done || !_started) {
      Navigator.of(context).pop();
      return;
    }
    _closing = true;
    final leave = await showDialog<bool>(
      context: context,
      barrierColor: PrepColors.scrim,
      builder: (context) => AlertDialog(
        title: const Text('Leave this lesson?'),
        content: const Text("Progress here won't be saved."),
        actions: [
          QuietButton('Keep going', onPressed: () => Navigator.of(context).pop(false)),
          QuietButton('Leave', color: PrepColors.danger, onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    _closing = false;
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  void _practiceAloud() {
    final then = widget.onPracticeAloud;
    Navigator.of(context).pop();
    then?.call();
  }

  void _choose(int index) {
    if (_checked) return;
    setState(() => _pick = index);
  }

  void _clearPick() {
    if (_checked) return;
    setState(() => _pick = null);
  }

  /// Places [step] in the first empty slot, top to bottom.
  void _place(int step) {
    final slot = _slots.indexOf(null);
    if (_checked || slot < 0) return;
    setState(() => _slots = List.of(_slots)..[slot] = step);
  }

  void _unplace(int slot) {
    if (_checked) return;
    setState(() => _slots = List.of(_slots)..[slot] = null);
  }

  AssistantMood get _mood {
    if (!_checked) return AssistantMood.idle;
    return _right ? AssistantMood.happy : AssistantMood.thinking;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final avail = size.height - padding.vertical - MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AmbientBackdrop(
        child: Scaffold(
          backgroundColor: const Color(0x00000000),
          body: SafeArea(bottom: false, child: _done ? _finished(avail) : _lessonView(avail)),
        ),
      ),
    );
  }

  // The lesson: top bar, the exercise (scrolls), and the bar that is Check, then the result card.

  Widget _lessonView(double avail) {
    final total = _lesson.exercises.length;
    final top = StepTopBar(
      progress: _resolved / total,
      progressLabel: 'Lesson progress, $_resolved of $total done',
      closeLabel: 'Close lesson',
      onClose: _close,
      caption: avail < 420 ? null : widget.skill.title,
      segments: total,
      count: '$_resolved/$total',
      metalClose: true,
    );
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _exercise(_current),
      ),
    );
    const inset = EdgeInsets.fromLTRB(Space.gutter, Space.m, Space.gutter, Space.xxl);
    final bar = _bar(_current, avail);
    if (avail < 300) {
      // Very short windows (landscape with large text): everything scrolls together.
      return SingleChildScrollView(
        controller: _scroll,
        child: Column(children: [top, Padding(padding: inset, child: body), bar]),
      );
    }
    return Column(
      children: [
        top,
        Expanded(
          child: SingleChildScrollView(controller: _scroll, padding: inset, child: body),
        ),
        bar,
      ],
    );
  }

  /// What to do and the question, with the robot in the top-right corner watching. When the line
  /// beside the robot would be too narrow (small phones, large text), the question drops under it
  /// at full width.
  Widget _head(DrillExercise exercise) {
    final robot = ExcludeSemantics(
      // The result card says the same in words.
      child: AssistantAvatar(look: widget.look, size: _robot, mood: _mood),
    );
    final instruction = Text(
      _isRetry ? 'Second try · ${exercise.instruction}' : exercise.instruction,
      style: PrepType.meta,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final beside = box.maxWidth - _robot - Space.m;
        final roomy = beside >= 240 * math.min(scale, 1.6);
        final style = scale > 1.3 || box.maxWidth < 340 ? PrepType.questionM : PrepType.question;
        final prompt = Semantics(header: true, child: Text(exercise.prompt, style: style));
        if (roomy) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: EnterFade(
                  key: ValueKey('head-$_index'),
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [instruction, const SizedBox(height: Space.s), prompt],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.m),
              robot,
            ],
          );
        }
        return EnterFade(
          key: ValueKey('head-$_index'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(padding: const EdgeInsets.only(bottom: Space.m), child: instruction),
                  ),
                  const SizedBox(width: Space.m),
                  robot,
                ],
              ),
              const SizedBox(height: Space.s),
              prompt,
            ],
          ),
        );
      },
    );
  }

  Widget _exercise(DrillExercise exercise) {
    final asked = exercise.asked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _head(exercise),
        EnterFade(
          key: ValueKey('answers-$_index'),
          child: KeyedSubtree(
            key: ValueKey('drill-exercise-${exercise.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (asked != null) ...[
                  const SizedBox(height: Space.l),
                  QuoteBlock(label: 'They ask', text: '“$asked”'),
                ],
                const SizedBox(height: Space.xxl),
                switch (exercise) {
                  ChoiceExercise e => _options(e.options, e.answer, 'Best answer'),
                  OddOneOutExercise e => _options(e.sentences, e.answer, "Doesn't belong"),
                  FillBlankExercise e => _fillBlank(e),
                  OrderExercise e => _order(e),
                  RewriteExercise e => _rewrite(e),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _options(List<String> options, int answer, String rightNote) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, text) in options.indexed) ...[
          if (i > 0) const SizedBox(height: Space.m),
          Builder(
            builder: (context) {
              final BoxTone tone;
              String? note;
              if (!_checked) {
                tone = i == _pick ? BoxTone.selected : BoxTone.idle;
              } else if (i == answer) {
                tone = BoxTone.correct;
                note = rightNote;
              } else if (i == _pick) {
                tone = BoxTone.wrong;
                note = 'Your pick';
              } else {
                tone = BoxTone.muted;
              }
              final box = AnswerBox(
                key: ValueKey('drill-option-$i'),
                text: text,
                tone: tone,
                note: note,
                onTap: _checked ? null : () => _choose(i),
                semanticLabel: '${i + 1} of ${options.length}: $text${note == null ? '' : '. $note'}',
              );
              return _checked && i == answer ? KeyedSubtree(key: _revealKey, child: box) : box;
            },
          ),
        ],
      ],
    );
  }

  Widget _fillBlank(FillBlankExercise e) {
    final pick = _pick;
    final gapTone = !_checked ? BoxTone.selected : (_right ? BoxTone.correct : BoxTone.wrong);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            style: (scale > 1.3 ? PrepType.titleL : PrepType.questionM).copyWith(color: PrepColors.text2),
            children: [
              if (e.before.isNotEmpty) TextSpan(text: e.before),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: BlankGap(
                  key: const ValueKey('drill-gap'),
                  word: pick == null ? null : e.bank[pick],
                  tone: gapTone,
                  onTap: _checked || pick == null ? null : _clearPick,
                ),
              ),
              TextSpan(text: e.after),
            ],
          ),
        ),
        const SizedBox(height: Space.xxl),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, word) in e.bank.indexed)
              Builder(
                builder: (context) {
                  // After a miss the right word lights up in the bank, so the answer is on screen.
                  final answer = _checked && !_right && i == e.answerIndex;
                  final tile = WordTile(
                    key: ValueKey('drill-tile-$i'),
                    text: word,
                    tone: !_checked ? BoxTone.idle : (answer ? BoxTone.correct : BoxTone.muted),
                    ghost: i == pick,
                    onTap: _checked ? null : () => _choose(i),
                    semanticLabel: answer ? '$word, the answer' : word,
                  );
                  return answer ? KeyedSubtree(key: _revealKey, child: tile) : tile;
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _order(OrderExercise e) {
    final labels = e.labels;
    final bank = [for (final step in e.start) if (!_slots.contains(step)) step];
    return AnimatedSize(
      duration: _still ? Duration.zero : Motion.fade,
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, step) in _slots.indexed) ...[
            if (i > 0) const SizedBox(height: Space.s),
            Builder(
              builder: (context) {
                var tone = step == null ? BoxTone.idle : BoxTone.selected;
                String? note;
                if (_checked && step != null) {
                  final label = labels == null ? null : labels[step];
                  if (step == i) {
                    tone = BoxTone.correct;
                    note = label ?? 'Right place';
                  } else {
                    tone = BoxTone.wrong;
                    note = label == null ? 'Goes in step ${step + 1}' : '$label · goes in step ${step + 1}';
                  }
                }
                return OrderSlot(
                  key: ValueKey('drill-slot-$i'),
                  number: i + 1,
                  text: step == null ? null : e.steps[step],
                  tone: tone,
                  note: note,
                  onTap: _checked || step == null ? null : () => _unplace(i),
                );
              },
            ),
          ],
          if (bank.isNotEmpty) ...[
            const SizedBox(height: Space.xxl),
            for (final (j, step) in bank.indexed) ...[
              if (j > 0) const SizedBox(height: Space.s),
              AnswerBox(
                key: ValueKey('drill-tile-$step'),
                text: e.steps[step],
                tone: BoxTone.idle,
                onTap: () => _place(step),
                semanticLabel: '${e.steps[step]}. Tap to place it in step ${_slots.indexOf(null) + 1}',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _rewrite(RewriteExercise e) {
    final count = drillWordCount(_text.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuoteBlock(label: 'Before', text: e.line),
        const SizedBox(height: Space.xxl),
        if (!_checked) ...[
          PrepTextField(
            fieldKey: const ValueKey('drill-rewrite-field'),
            controller: _text,
            label: 'Your version',
            hint: 'Write it here',
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: Space.s),
          Text(
            count < RewriteExercise.minWords
                ? 'At least ${RewriteExercise.minWords} words ($count so far)'
                : '$count words',
            style: PrepType.meta,
          ),
        ] else ...[
          QuoteBlock(label: 'Yours', text: _text.text.trim()),
          const SizedBox(height: Space.m),
          EnterFade(
            key: _revealKey,
            child: QuoteBlock(label: 'One way to say it', text: e.model, strong: true),
          ),
        ],
      ],
    );
  }

  /// The bottom of the lesson: Check, then (the one authored moment) a result card sliding up in
  /// its place, tinted for right or not quite, with the reason and Continue.
  Widget _bar(DrillExercise exercise, double avail) {
    final duration = _still ? Duration.zero : Motion.enter;
    final Widget content = !_checked
        ? BottomActionBar(
            color: const Color(0x00000000),
            children: [
              PrimaryButton('Check', key: const ValueKey('drill-check'), onPressed: _canCheck ? _check : null),
            ],
          )
        : SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: Space.m),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: _result(exercise, avail),
                ),
              ),
            ),
          );
    return AnimatedSize(
      duration: duration,
      curve: Motion.standard,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Motion.decelerate,
        switchOutCurve: Motion.standard,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey('bar-$_index-$_checked'), child: content),
      ),
    );
  }

  Widget _result(DrillExercise exercise, double avail) {
    final rewrite = exercise is RewriteExercise;
    final status = rewrite ? null : (_right ? PrepColors.success : PrepColors.warning);
    return MetalCard(
      hero: true,
      radius: Radii.sheet,
      tint: status,
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(96, avail * 0.32)),
            child: SingleChildScrollView(child: _feedback(exercise, status)),
          ),
          const SizedBox(height: Space.l),
          PrimaryButton('Continue', key: const ValueKey('drill-continue'), onPressed: _continue),
        ],
      ),
    );
  }

  Widget _feedback(DrillExercise exercise, Color? status) {
    final reason = PrepType.bodyL.copyWith(color: PrepColors.text2);
    if (exercise is RewriteExercise) {
      return Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ResultTitle(
              mark: StatusMark(PrepIcons.edit, color: PrepColors.surface2, ink: PrepColors.text, size: 32),
              title: 'Compare yours',
              color: PrepColors.text,
            ),
            const SizedBox(height: Space.m),
            Text(rewriteTip(exercise, _text.text), style: reason),
          ],
        ),
      );
    }
    final why = switch (exercise) {
      ChoiceExercise e => e.why,
      OddOneOutExercise e => e.why,
      FillBlankExercise e => e.why,
      OrderExercise e => e.why,
      RewriteExercise _ => '',
    };
    // A missed blank leads with the word, so the answer is in words as well as in the bank.
    final answer = !_right && exercise is FillBlankExercise ? exercise.answer : null;
    final color = status ?? PrepColors.text;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResultTitle(
            mark: StatusMark(_right ? PrepIcons.check : PrepIcons.close, color: color, size: 32),
            title: _right ? 'Nice.' : 'Not quite.',
            color: color,
          ),
          const SizedBox(height: Space.m),
          Text.rich(
            TextSpan(
              children: [
                if (answer != null)
                  TextSpan(text: 'Answer: $answer. ', style: PrepType.bodyLMedium.copyWith(color: PrepColors.text)),
                TextSpan(text: why),
              ],
            ),
            style: reason,
          ),
          if (!_right && !_isRetry) ...[
            const SizedBox(height: Space.m),
            Row(
              children: [
                PrepIcon(PrepIcons.replay, color: PrepColors.text2, size: 16),
                const SizedBox(width: Space.s),
                Expanded(child: Text('Comes back at the end', style: PrepType.meta)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // The finish: the robot pleased on its lit floor, the first-try count as a number, one line
  // about the effort, and the idea to keep. No streaks, points or confetti.

  Widget _finished(double avail) {
    final total = _lesson.scoredCount;
    final missed = _missed.length;
    final correct = total - missed;
    final robot = (avail * 0.36).clamp(120.0, 300.0);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xxl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: EnterFade(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ExcludeSemantics(
                          // The dial's arc is the first-try share: a real measure, not decoration.
                          child: RobotStage(
                            look: widget.look,
                            robotSize: robot,
                            mood: AssistantMood.happy,
                            progress: total == 0 ? null : correct / total,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.l),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text('Lesson complete', style: PrepType.display, textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: Space.l),
                      MergeSemantics(
                        child: Column(
                          children: [
                            Text(
                              '$correct/$total',
                              key: const ValueKey('drill-score'),
                              semanticsLabel: '$correct of $total',
                              style: PrepType.numeral,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: Space.xs),
                            Text('right first time', style: PrepType.meta, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.m),
                      Text(_encouragement(missed, total), style: PrepType.bodyL.copyWith(color: PrepColors.text2), textAlign: TextAlign.center),
                      const SizedBox(height: Space.x3),
                      _Takeaway(text: _lesson.takeaway),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        BottomActionBar(
          color: const Color(0x00000000),
          children: [
            PrimaryButton('Done', key: const ValueKey('drill-done'), onPressed: () => Navigator.of(context).pop()),
            if (widget.onPracticeAloud != null) ...[
              const SizedBox(height: Space.xs),
              QuietButton(
                'Practice aloud',
                key: const ValueKey('drill-aloud'),
                icon: PrepIcons.mic,
                onPressed: _practiceAloud,
              ),
            ],
          ],
        ),
      ],
    );
  }

  static String _encouragement(int missed, int total) {
    if (total == 0) return 'Every exercise done.';
    if (missed == 0) return 'Steady work.';
    if (missed == 1) return 'You fixed the one you missed.';
    return 'You fixed the $missed you missed.';
  }
}

/// The result card's first line: a status mark and "Nice." or "Not quite.".
class _ResultTitle extends StatelessWidget {
  const _ResultTitle({required this.mark, required this.title, required this.color});

  final Widget mark;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        mark,
        const SizedBox(width: Space.m),
        Expanded(child: Text(title, style: PrepType.titleL.copyWith(color: color))),
      ],
    );
  }
}

/// The lesson's one idea, kept on the finish screen.
class _Takeaway extends StatelessWidget {
  const _Takeaway({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return MetalCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: PrepIcon(PrepIcons.target, color: PrepColors.text2, size: 20),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remember', style: PrepType.label.copyWith(color: PrepColors.text2)),
                const SizedBox(height: Space.xs),
                Text(text, style: PrepType.bodyLMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
