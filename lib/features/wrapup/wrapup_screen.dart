import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../coach/coach_api.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';
import '../interview/read_aloud.dart';

/// The end of a practice: what to remember. The coach, pleased; a heading; the numbered
/// last-minute notes on one metal card; tips and the stories worth telling wait in a sheet under
/// "More"; one obvious way out. [review] opens notes that were
/// already written (from Home, Practice or History).
class WrapupScreen extends StatefulWidget {
  const WrapupScreen({super.key, required this.session, this.review = false});

  final PracticeSession session;
  final bool review;

  @override
  State<WrapupScreen> createState() => _WrapupScreenState();
}

class _WrapupScreenState extends State<WrapupScreen> with WidgetsBindingObserver {
  late AppServices _services;
  ReadAloud? _reader;
  final _voiceLevel = LevelMix();
  bool _listening = false;
  bool _loading = false;
  CoachException? _error;
  bool _started = false;
  bool _requestInFlight = false;

  Wrapup? get _wrapup => widget.session.wrapup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceLevel.dispose();
    final reader = _reader;
    if (reader != null) {
      reader.hush();
      reader.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) _reader?.hush();
  }

  /// Norman reads the last-minute notes only when asked: they are often read somewhere public.
  void _toggleNotes(Wrapup wrapup) {
    final reader = _reader;
    if (reader == null) return;
    if (reader.current == Spoken.notes) {
      reader.hush();
      return;
    }
    final text = wrapup.lastMinuteNotes.map(speakable).where((n) => n.isNotEmpty).join(' ');
    reader.say(Spoken.notes, text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    _reader ??= ReadAloud(_services.voice);
    if (!_listening) {
      _listening = true;
      _voiceLevel.listenTo(_services.voice.level);
    }
    if (!_started) {
      _started = true;
      if (_wrapup == null) {
        _loading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    }
  }

  Future<void> _load() async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wrapup = await _services.coach.wrapup(
        job: widget.session.job,
        answers: widget.session.summaries(),
        about: _services.profile.value.about,
      );
      widget.session.wrapup = wrapup;
      // Finish an in-flight save after leaving this page, but never replace a
      // newer practice or restore notes the person has explicitly deleted.
      if (identical(_services.sessions.last, widget.session)) {
        await _services.sessions.finished(widget.session);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } on CoachException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = CoachException(CoachErrorKind.badResponse, message: '$e');
      });
    } finally {
      _requestInFlight = false;
    }
  }

  AssistantMood get _mood {
    if (_reader?.current != null) return AssistantMood.speaking;
    if (_loading) return AssistantMood.thinking;
    return _wrapup != null ? AssistantMood.happy : AssistantMood.idle;
  }

  void _done() {
    _reader?.hush();
    final navigator = Navigator.of(context);
    // Notes opened for review go back to where they were opened (Home or Profile); a finished
    // practice goes home.
    if (widget.review) {
      navigator.maybePop();
    } else {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reader = _reader!;
    return ListenableBuilder(
      listenable: Listenable.merge([reader, _services.sessions]),
      builder: (context, _) {
        final wrapup = _wrapup;
        final status = _loading
            ? 'Writing your notes'
            : reader.current == Spoken.notes
                ? 'Reading your notes'
                : wrapup != null
                    ? 'Notes ready'
                    : "Couldn't write your notes";
        final canHear = wrapup != null && wrapup.lastMinuteNotes.isNotEmpty;
        return CoachScaffold(
          onClose: _done,
          progress: 1,
          progressLabel: 'Practice complete',
          segments: widget.session.questions.isEmpty ? 1 : widget.session.questions.length,
          dock: _dock(wrapup),
          builder: (context, room) => [
            CoachStage(
              mood: _mood,
              status: status,
              level: _voiceLevel,
              size: _coachSize(context),
              progress: wrapup != null ? 1 : null,
              side: canHear
                  ? ReadAloudButton(
                      key: const ValueKey('hear-notes'),
                      iconOnly: true,
                      label: 'Hear your notes',
                      stopLabel: 'Stop reading your notes',
                      speaking: reader.current == Spoken.notes,
                      onPressed: () => _toggleNotes(wrapup),
                    )
                  : null,
            ),
            const SizedBox(height: Space.l),
            Semantics(
              header: true,
              child: Text('Before your interview', style: PrepType.display, textAlign: TextAlign.center),
            ),
            if (wrapup?.mock ?? false) ...[
              const SizedBox(height: Space.xs),
              Text('Sample notes', style: PrepType.caption, textAlign: TextAlign.center),
            ],
            const SizedBox(height: Space.xl),
            if (wrapup != null)
              _Notes(wrapup.lastMinuteNotes)
            else if (_error != null)
              ProblemNote(title: "Couldn't write your notes.", body: _error!.userMessage, centered: true)
            else if (_loading)
              const LoadingLine('Putting your notes together'),
            if (_services.sessions.saveFailed) ...[
              const SizedBox(height: Space.xxl),
              const ProblemNote(title: 'Notes are not saved yet.', body: 'Try saving again.', centered: true),
            ],
          ],
        );
      },
    );
  }

  /// The coach celebrating the finished practice: a step smaller than on a question, so the notes
  /// have the page.
  double _coachSize(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = media.textScaler.scale(16) / 16;
    return (media.size.height * 0.24 / scale).clamp(compactCoachSize(context), 220).toDouble();
  }

  /// One obvious next step: finish, or fix whatever stopped the notes being written or saved.
  Widget? _dock(Wrapup? wrapup) {
    final done = DockAction(icon: PrepIcons.check, label: 'Done', onPressed: _done);
    if (_error != null && wrapup == null) return PillDock(label: 'Try again', onPressed: _load, leading: done);
    if (_services.sessions.saveFailed) {
      return PillDock(label: 'Save again', onPressed: () => _services.sessions.finished(widget.session), leading: done);
    }
    if (wrapup == null) return null;
    final more = wrapup.tips.isNotEmpty || wrapup.storiesToUse.isNotEmpty;
    return PillDock(
      label: 'Done',
      onPressed: _done,
      leading: more
          ? DockAction(
              icon: PrepIcons.layers,
              label: 'More',
              semanticLabel: 'More: tips and stories',
              onPressed: () => _openMore(wrapup),
            )
          : null,
    );
  }

  /// Tips and stories wait in a sheet, so the notes stand alone on the page.
  void _openMore(Wrapup wrapup) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _MoreSheet(tips: wrapup.tips, stories: wrapup.storiesToUse),
    );
  }
}

/// The last-minute notes, numbered, on one metal card: the part to read just before walking in.
class _Notes extends StatelessWidget {
  const _Notes(this.notes);

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return Text('No notes this time.', style: PrepType.bodyL, textAlign: TextAlign.center);
    final numberWidth = MediaQuery.textScalerOf(context).scale(28);
    final number = PrepType.numeral.copyWith(fontSize: 28, height: 1, color: PrepColors.text3);
    return MetalCard(
      hero: true,
      radius: Radii.sheet,
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < notes.length; i++) ...[
            if (i > 0) const Hairline(),
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.l),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(width: numberWidth, child: Text('${i + 1}', style: number)),
                    const SizedBox(width: Space.m),
                    Expanded(child: Text(notes[i], style: PrepType.titleL)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The sheet under "More": tips, then the stories worth telling.
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.tips, required this.stories});

  final List<String> tips;
  final List<String> stories;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xxl + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ListSection(title: 'Tips', icon: PrepIcons.check, items: tips),
            if (tips.isNotEmpty && stories.isNotEmpty) const SizedBox(height: Space.x3),
            _ListSection(title: 'Stories to use', icon: PrepIcons.chat, items: stories),
          ],
        ),
      ),
    );
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({required this.title, required this.icon, required this.items});

  final String title;
  final PrepIcons icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Row(
            children: [
              PrepIcon(icon, color: PrepColors.text2, size: 18),
              const SizedBox(width: Space.s),
              Expanded(child: Text(title, style: PrepType.titleM)),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Hairline(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.m),
            child: Text(items[i], style: PrepType.bodyL),
          ),
        ],
      ],
    );
  }
}
