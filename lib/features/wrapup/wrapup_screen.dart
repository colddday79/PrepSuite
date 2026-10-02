import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../coach/coach_api.dart';
import '../../design/assistant_avatar.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';
import '../interview/read_aloud.dart';

/// The end of a practice: what to remember. The last-minute notes come first and largest, then
/// tips and the stories worth telling, each in its own card, and one obvious way out. [review]
/// opens notes that were already written (from Home, Practice or History).
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
        final answered = widget.session.answers.length;
        final status = _loading
            ? 'Writing your notes'
            : reader.current == Spoken.notes
                ? 'Reading your notes'
                : wrapup != null
                    ? 'Your notes are ready'
                    : "Couldn't write your notes";
        return CoachScaffold(
          onClose: _done,
          progress: 1,
          progressLabel: 'Practice complete',
          caption: '${widget.session.jobTitle} · $answered ${answered == 1 ? 'answer' : 'answers'}',
          actions: _actions(wrapup),
          children: [
            CoachLine(mood: _mood, status: status, level: _voiceLevel),
            const SizedBox(height: Space.xl),
            Semantics(header: true, child: Text('Before your interview', style: PrepType.headline)),
            if (wrapup?.mock ?? false) ...[
              const SizedBox(height: Space.xs),
              Text('Sample notes', style: PrepType.caption),
            ],
            if (wrapup != null && wrapup.lastMinuteNotes.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Transform.translate(
                  offset: const Offset(-Space.m, 0),
                  child: ReadAloudButton(
                    label: 'Hear your notes',
                    stopLabel: 'Stop reading your notes',
                    speaking: reader.current == Spoken.notes,
                    onPressed: () => _toggleNotes(wrapup),
                  ),
                ),
              ),
              const SizedBox(height: Space.s),
            ] else
              const SizedBox(height: Space.l),
            if (wrapup != null) ...[
              CoachCard(child: _Notes(wrapup.lastMinuteNotes)),
              _ListSection(title: 'Tips', icon: PrepIcons.check, items: wrapup.tips),
              _ListSection(title: 'Stories to use', icon: PrepIcons.chat, items: wrapup.storiesToUse),
            ] else if (_error != null)
              ProblemNote(title: "Couldn't write your notes.", body: _error!.userMessage)
            else if (_loading)
              const LoadingLine('Putting your notes together'),
            if (_services.sessions.saveFailed) ...[
              const SizedBox(height: Space.xxl),
              const ProblemNote(title: 'Notes are not saved yet.', body: 'Try saving again.'),
            ],
          ],
        );
      },
    );
  }

  /// One obvious next step: finish, or fix whatever stopped the notes being written or saved.
  List<Widget> _actions(Wrapup? wrapup) {
    if (_error != null && wrapup == null) {
      return [
        PrimaryButton('Try again', onPressed: _load),
        QuietRow([QuietButton('Done', onPressed: _done)]),
      ];
    }
    if (_services.sessions.saveFailed) {
      return [
        PrimaryButton('Save again', onPressed: () => _services.sessions.finished(widget.session)),
        QuietRow([QuietButton('Done', onPressed: _done)]),
      ];
    }
    if (wrapup == null) return const [];
    return [PrimaryButton('Done', onPressed: _done)];
  }
}

/// The last-minute notes, numbered: the part to read just before walking in.
class _Notes extends StatelessWidget {
  const _Notes(this.notes);

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return Text('No notes this time.', style: PrepType.bodyL);
    final numberWidth = MediaQuery.textScalerOf(context).scale(24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < notes.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == notes.length - 1 ? 0 : Space.l),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: numberWidth,
                    child: Text(
                      '${i + 1}',
                      style: PrepType.questionM.copyWith(
                        color: PrepColors.text3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(notes[i], style: PrepType.questionM)),
                ],
              ),
            ),
          ),
      ],
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
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: CoachCard(
        title: title,
        icon: icon,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: Space.m), child: Hairline()),
              Text(items[i], style: PrepType.bodyL.copyWith(color: PrepColors.text2)),
            ],
          ],
        ),
      ),
    );
  }
}
