import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../coach/coach_api.dart';
import '../../design/components.dart';
import '../../design/frosted_panel.dart';
import '../../design/hologram.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';

const double _presenceSize = 150;
const double _barHeight = 64;

/// Step three: what to remember. The last-minute notes come first and largest, then tips and the
/// stories worth telling. [review] opens notes that were already written (from Home).
class WrapupScreen extends StatefulWidget {
  const WrapupScreen({super.key, required this.session, this.review = false});

  final PracticeSession session;
  final bool review;

  @override
  State<WrapupScreen> createState() => _WrapupScreenState();
}

class _WrapupScreenState extends State<WrapupScreen> {
  late AppServices _services;
  bool _loading = false;
  CoachException? _error;
  bool _started = false;
  bool _requestInFlight = false;

  Wrapup? get _wrapup => widget.session.wrapup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
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
      final wrapup = await _services.coach.wrapup(job: widget.session.job, answers: widget.session.summaries());
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

  void _done() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final wrapup = _wrapup;
    final answered = widget.session.answers.length;
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: PresenceBackdrop(
            top: _barHeight,
            size: _presenceSize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CoachTopBar(
                  status: '${widget.session.jobTitle} · $answered ${answered == 1 ? 'answer' : 'answers'}',
                  onClose: _done,
                ),
                // The panel starts below the presence, in its light, and never covers it.
                const SizedBox(height: _presenceSize + Space.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: FrostedPanel(
                    padding: const EdgeInsets.fromLTRB(Space.xxl, Space.xxl, Space.xxl, Space.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wrapup?.mock ?? false) ...[
                          Text('Sample notes', style: PrepType.label.copyWith(color: PrepColors.accent)),
                          const SizedBox(height: Space.s),
                        ],
                        Semantics(header: true, child: Text('Before your interview', style: PrepType.headline)),
                        const SizedBox(height: Space.xs),
                        Text('Read these last-minute notes just before you walk in.', style: PrepType.meta),
                        const SizedBox(height: Space.xxl),
                        if (wrapup != null)
                          ..._notes(wrapup.lastMinuteNotes)
                        else if (_error != null) ...[
                          ProblemNote(title: "Couldn't write your notes.", body: _error!.userMessage),
                          const SizedBox(height: Space.xxl),
                          PrimaryButton('Try again', onPressed: _load),
                        ] else if (_loading)
                          const LoadingLine('Putting your notes together'),
                      ],
                    ),
                  ),
                ),
                if (wrapup != null) ...[
                  _ListSection(title: 'Tips', items: wrapup.tips),
                  _ListSection(title: 'Stories to use', items: wrapup.storiesToUse),
                ],
                ListenableBuilder(
                  listenable: _services.sessions,
                  builder: (context, _) => !_services.sessions.saveFailed
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.all(Space.gutter),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProblemNote(title: 'Notes are not saved yet.', body: 'Keep this screen open and try saving again before closing the app.'),
                              const SizedBox(height: Space.m),
                              PrimaryButton('Save again', onPressed: () => _services.sessions.finished(widget.session)),
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.xxl),
                  child: wrapup != null || _error != null
                      ? PrimaryButton('Done', onPressed: _done)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _notes(List<String> notes) {
    if (notes.isEmpty) return [Text('No notes this time. Look over the tips below.', style: PrepType.bodyL)];
    return [
      for (var i = 0; i < notes.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == notes.length - 1 ? 0 : Space.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 24, child: Text('${i + 1}', style: PrepType.questionM.copyWith(color: PrepColors.accent))),
              const SizedBox(width: Space.s),
              Expanded(child: Text(notes[i], style: PrepType.questionM)),
            ],
          ),
        ),
    ];
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.s),
          child: Semantics(header: true, child: Text(title, style: PrepType.titleM)),
        ),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Hairline(indent: Space.gutter),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
            child: Text(items[i], style: PrepType.bodyL.copyWith(color: PrepColors.text2)),
          ),
        ],
      ],
    );
  }
}
