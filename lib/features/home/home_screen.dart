import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/session.dart';
import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../coach/speech_adapter.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';
import '../consent/consent_sheet.dart';
import '../interview/interview_screen.dart';
import '../wrapup/wrapup_screen.dart';

const _maxJobRecording = Duration(seconds: 10);
const double _barHeight = 56;

/// The presence never gets smaller than this, even when the keyboard is up.
const double _minStage = 220;
const double _minStageWithKeyboard = 96;

enum _Phase { idle, preparing, recording, transcribing, review, typing, unheard, micOff, loading, error }

/// Where practice starts. The gold presence fills the top of the screen and nothing sits over it.
/// Below it the person says the job and the kind of interview (ten seconds at most) or types it,
/// checks what was heard, and the coach writes questions for exactly that.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AppServices _services;
  final _level = LevelMix();
  final _progress = ValueNotifier<double>(0);
  final _job = TextEditingController();

  /// While the coach writes questions the presence breathes on its own.
  late final AnimationController _think = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final Animation<double> _thinking = Tween<double>(begin: 0.05, end: 0.45)
      .animate(CurvedAnimation(parent: _think, curve: Curves.easeInOut));

  StreamSubscription<String>? _partialSub;
  Timer? _ticker;
  _Phase _phase = _Phase.idle;
  String _partial = '';
  bool _typedJob = false;
  bool _micBlocked = false;
  bool _micFailed = false;
  String? _speechError;
  CoachException? _error;
  int _operation = 0;
  bool _submitting = false;
  bool _wired = false;
  Future<bool>? _consentRequest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    if (_wired) return;
    _wired = true;
    _level.listenTo(_services.speech.level);
    _partialSub = _services.speech.partialText.listen((text) {
      if (mounted && _phase == _Phase.recording) setState(() => _partial = text);
    });
    _services.speechSetup.state.addListener(_onSpeechSetup);
    unawaited(_services.speechSetup.prepare().catchError((Object _) {}));
    // First run: explain what happens to the person's voice before anything else.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await _ensureConsent();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operation++;
    _ticker?.cancel();
    _partialSub?.cancel();
    _services.speechSetup.state.removeListener(_onSpeechSetup);
    _services.speech.cancel();
    HologramVideo.instance.setBusy(false);
    _think.dispose();
    _level.dispose();
    _progress.dispose();
    _job.dispose();
    super.dispose();
  }

  void _onSpeechSetup() {
    if (mounted) setState(() {});
  }

  SpeechReadiness get _setup => _services.speechSetup.state.value;

  Future<bool> _ensureConsent() => _consentRequest ??= _requestConsent().whenComplete(() => _consentRequest = null);

  Future<bool> _requestConsent() async {
    if (await _services.consent.accepted()) return true;
    if (!mounted) return false;
    if (!await showConsentSheet(context)) return false;
    await _services.consent.accept();
    return true;
  }

  Future<void> _record() async {
    if (_phase == _Phase.recording) return _stop();
    if (_phase == _Phase.preparing || _phase == _Phase.transcribing || _phase == _Phase.loading) return;
    if (!_setup.isReady) {
      if (_setup.isFailed) _typeInstead();
      return;
    }
    final operation = ++_operation;
    setState(() {
      _phase = _Phase.preparing;
      _speechError = null;
    });
    try {
      if (!await _ensureConsent()) {
        if (mounted && operation == _operation) setState(() => _phase = _Phase.idle);
        return;
      }
      if (!mounted || operation != _operation) return;
      final access = await _services.mic.request();
      if (!mounted || operation != _operation) return;
      if (access != MicAccess.granted) {
        setState(() {
          _micBlocked = access == MicAccess.blocked;
          _micFailed = false;
          _phase = _Phase.micOff;
        });
        return;
      }
      final started = await _services.speech.start(maxDuration: _maxJobRecording);
      if (!mounted || operation != _operation) {
        if (started) await _services.speech.cancel();
        return;
      }
      if (!started) throw StateError('Speech capture could not start');
    } catch (_) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _micBlocked = false;
        _micFailed = true;
        _speechError = speechErrorMessage(_services.speech);
        _phase = _Phase.micOff;
      });
      return;
    }
    var elapsed = 0;
    _progress.value = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed += 100;
      _progress.value = elapsed / _maxJobRecording.inMilliseconds;
      if (elapsed >= _maxJobRecording.inMilliseconds) _stop();
    });
    setState(() {
      _partial = '';
      _phase = _Phase.recording;
    });
  }

  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    setState(() => _phase = _Phase.transcribing);
    CaptureResult? result;
    try {
      result = await _services.speech.stop();
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    _level.rest();
    _progress.value = 0;
    final heard = result?.transcript.text.trim() ?? '';
    if (heard.isEmpty) {
      setState(() => _phase = _Phase.unheard);
      return;
    }
    _job.text = heard;
    setState(() {
      _typedJob = false;
      _phase = _Phase.review;
    });
  }

  /// Typing the job means practising quietly: questions show as text and answers are typed.
  void _typeInstead() {
    _operation++;
    _ticker?.cancel();
    _services.speech.cancel();
    _progress.value = 0;
    if (_phase != _Phase.review) _job.clear();
    setState(() {
      _typedJob = true;
      _phase = _Phase.typing;
    });
  }

  Future<void> _submit() async {
    // Set before any await, so a double tap can never send the job twice.
    if (_submitting) return;
    final job = _job.text.trim();
    if (job.isEmpty) return;
    _submitting = true;
    try {
      FocusScope.of(context).unfocus();
      if (!await _ensureConsent() || !mounted) return;
      final operation = ++_operation;
      setState(() {
        _error = null;
        _phase = _Phase.loading;
      });
      _busy(true);
      try {
        final set = await _services.coach.questions(job: job, count: 5);
        if (!mounted || operation != _operation) return;
        final session = PracticeSession(job: job, set: set, preferTyping: _typedJob || _setup.isFailed);
        _busy(false);
        setState(() => _phase = _Phase.idle);
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InterviewScreen(session: session)));
        if (!mounted) return;
        _job.clear();
        setState(() {
          _partial = '';
          _typedJob = false;
          _phase = _Phase.idle;
        });
      } on CoachException catch (e) {
        _failed(operation, e);
      } catch (e) {
        _failed(operation, CoachException(CoachErrorKind.badResponse, message: '$e'));
      }
    } finally {
      _submitting = false;
    }
  }

  void _failed(int operation, CoachException error) {
    _busy(false);
    if (!mounted || operation != _operation) return;
    setState(() {
      _error = error;
      _phase = _Phase.error;
    });
  }

  void _busy(bool busy) {
    HologramVideo.instance.setBusy(busy);
    if (busy && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _think.repeat(reverse: true);
    } else {
      _think.stop();
      _think.value = 0;
    }
  }

  void _changeJob() => setState(() => _phase = _typedJob ? _Phase.typing : _Phase.review);

  void _openNotes() {
    final last = _services.sessions.last;
    if (last == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WrapupScreen(session: last, review: true)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused && state != AppLifecycleState.detached) return;
    if (_phase == _Phase.recording) {
      unawaited(_stop());
    } else if (_phase == _Phase.preparing) {
      _operation++;
      _services.speech.cancel();
      setState(() => _phase = _Phase.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: PrepColors.bg,
      body: LayoutBuilder(
        builder: (context, box) {
          final minStage = insets.top + (keyboard ? _minStageWithKeyboard : _minStage);
          // The presence takes whatever the controls leave, so it is as big as the screen allows.
          return Column(
            children: [
              Expanded(child: _stage(insets.top)),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: math.max(0, box.maxHeight - minStage)),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, insets.bottom + Space.l),
                  child: AnimatedSize(
                    duration: Motion.enter,
                    curve: Motion.decelerate,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: _content(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stage(double topInset) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        HologramHero(top: topInset + _barHeight, level: _phase == _Phase.loading ? _thinking : _level),
        // The wordmark and settings sit in the corners the round presence leaves empty.
        Positioned(
          top: topInset,
          left: 0,
          right: 0,
          height: _barHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.gutter, right: Space.s),
            child: Row(
              children: [
                Expanded(child: Text('PrepSuite', style: PrepType.wordmark)),
                IconAction(PrepIcons.sliders, label: 'Settings', plain: true, onPressed: () => showSettingsSheet(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _content() {
    switch (_phase) {
      // Idle, recording and the moments around it share one layout, so the button never moves
      // under a finger.
      case _Phase.idle:
      case _Phase.preparing:
      case _Phase.recording:
      case _Phase.transcribing:
        if (_setup.isFailed) return _voiceMissing();
        return _speak();
      case _Phase.review:
      case _Phase.typing:
        return _confirm();
      case _Phase.unheard:
        return [
          ..._headline(),
          const ProblemNote(
            title: "We couldn't hear that.",
            body: 'Check that nothing is covering the microphone and speak a little louder. Or type the job instead.',
            center: true,
          ),
          const SizedBox(height: Space.l),
          Center(child: MicButton(recording: false, progress: _progress, onPressed: _record)),
          const SizedBox(height: Space.s),
          _links(),
        ];
      case _Phase.micOff:
        return [
          ..._headline(),
          ProblemNote(
            title: _micFailed ? "The microphone didn't start." : 'The microphone is off.',
            body: _micFailed
                ? _speechError ?? 'Another app may be using it. Try again, or type the job instead.'
                : _micBlocked
                    ? 'Allow the microphone for PrepSuite in Settings, or type the job instead.'
                    : 'PrepSuite needs the microphone to hear you. You can allow it when you try again, or type the job instead.',
            center: true,
          ),
          const SizedBox(height: Space.xl),
          PrimaryButton('Type instead', onPressed: _typeInstead),
          const SizedBox(height: Space.s),
          Center(
            child: QuietButton(
              _micBlocked ? 'Open settings' : 'Try again',
              onPressed: _micBlocked ? _services.mic.openSettings : _record,
            ),
          ),
        ];
      case _Phase.loading:
        return [
          Text(_job.text.trim(), style: PrepType.question, textAlign: TextAlign.center),
          const SizedBox(height: Space.xl),
          const LoadingLine('Writing questions for this role', center: true),
          const SizedBox(height: Space.x3),
        ];
      case _Phase.error:
        return [
          ProblemNote(
            title: "Couldn't get your questions.",
            body: _error?.userMessage ?? 'Something went wrong. Try again.',
            center: true,
          ),
          const SizedBox(height: Space.xl),
          PrimaryButton('Try again', onPressed: _submit),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Change the job', onPressed: _changeJob)),
        ];
    }
  }

  List<Widget> _headline() => [
        Semantics(
          header: true,
          child: Text("What's the interview for?", style: PrepType.display, textAlign: TextAlign.center),
        ),
        const SizedBox(height: Space.s),
      ];

  List<Widget> _speak() {
    final recording = _phase == _Phase.recording;
    final ready = _setup.isReady;
    final busy = _phase == _Phase.preparing || _phase == _Phase.transcribing;
    return [
      ..._headline(),
      // Two lines are kept for the words as they are heard, so nothing below moves.
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Center(
          child: recording
              ? Semantics(
                  liveRegion: true,
                  child: Text(
                    _partial.isEmpty ? 'Listening' : _tail(_partial),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: PrepType.bodyL.copyWith(color: _partial.isEmpty ? PrepColors.text3 : PrepColors.text),
                  ),
                )
              : Text(
                  'Say the job and the kind of interview, like “barista, group interview”.',
                  textAlign: TextAlign.center,
                  style: PrepType.body,
                ),
        ),
      ),
      const SizedBox(height: Space.l),
      Center(
        child: MicButton(
          recording: recording,
          progress: _progress,
          onPressed: ready && !busy ? _record : null,
        ),
      ),
      const SizedBox(height: Space.s),
      if (!ready)
        _SetupProgress(setup: _setup)
      else
        ValueListenableBuilder<double>(
          valueListenable: _progress,
          builder: (context, p, _) {
            final String hint;
            if (recording) {
              final left = ((1 - p.clamp(0.0, 1.0)) * _maxJobRecording.inSeconds).ceil();
              hint = '$left s left. Tap to stop.';
            } else if (_phase == _Phase.transcribing) {
              hint = 'Turning your voice into text';
            } else if (_phase == _Phase.preparing) {
              hint = 'Starting the microphone';
            } else {
              hint = 'Tap and talk. You have 10 seconds.';
            }
            return Text(hint, textAlign: TextAlign.center, style: PrepType.meta);
          },
        ),
      const SizedBox(height: Space.s),
      Visibility(visible: !recording && !busy, maintainSize: true, maintainAnimation: true, maintainState: true, child: _links()),
    ];
  }

  List<Widget> _confirm() {
    final typing = _phase == _Phase.typing;
    return [
      ..._headline(),
      Text(
        typing
            ? 'Type the job and the kind of interview. The questions show as text and you type your answers.'
            : "Here's what we heard. Fix anything we got wrong.",
        textAlign: TextAlign.center,
        style: PrepType.body,
      ),
      const SizedBox(height: Space.l),
      PrepTextField(
        fieldKey: const ValueKey('job-field'),
        controller: _job,
        hint: 'For example: barista, group interview',
        minLines: 2,
        autofocus: typing && _job.text.isEmpty,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Space.xl),
      PrimaryButton('Use this', onPressed: _job.text.trim().isEmpty ? null : _submit),
      const SizedBox(height: Space.s),
      if (!_setup.isFailed)
        Center(
          child: QuietButton(
            typing ? 'Say it instead' : 'Record again',
            icon: typing ? PrepIcons.mic : PrepIcons.replay,
            onPressed: _record,
          ),
        ),
    ];
  }

  List<Widget> _voiceMissing() {
    final note = _setup.error ?? 'Voice is not available on this phone.';
    return [
      ..._headline(),
      ProblemNote(
        title: "Voice isn't available.",
        body: kDebugMode && _setup.missing ? '$note (Developers: run tools/voice/fetch_models.sh, then rebuild.)' : note,
        center: true,
      ),
      const SizedBox(height: Space.xl),
      PrimaryButton('Type the job', onPressed: _typeInstead),
      const SizedBox(height: Space.s),
      _links(typing: false),
    ];
  }

  /// The quiet ways out: typing instead of talking, and the notes from the last practice.
  Widget _links({bool typing = true}) {
    return ListenableBuilder(
      listenable: _services.sessions,
      builder: (context, _) {
        final last = _services.sessions.last;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.s,
          children: [
            if (typing) QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: _typeInstead),
            if (last != null)
              QuietButton(
                last.wrapup == null ? 'Finish your notes' : 'Last-minute notes',
                icon: PrepIcons.write,
                onPressed: _openNotes,
              ),
          ],
        );
      },
    );
  }
}

/// The last words heard, so a long job still ends on what was just said.
String _tail(String text, [int max = 72]) {
  final t = text.trim();
  if (t.length <= max) return t;
  final cut = t.substring(t.length - max);
  final space = cut.indexOf(' ');
  return '…${space < 0 ? cut : cut.substring(space + 1)}';
}

/// First-launch set-up of the offline speech files, said plainly with real progress.
class _SetupProgress extends StatelessWidget {
  const _SetupProgress({required this.setup});

  final SpeechReadiness setup;

  @override
  Widget build(BuildContext context) {
    final percent = (setup.progress * 100).floor();
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          Text(
            setup.copying ? 'Setting up the voice on this phone' : 'Getting the voice ready',
            textAlign: TextAlign.center,
            style: PrepType.bodyLMedium,
          ),
          const SizedBox(height: Space.xs),
          Text(
            setup.copying
                ? 'First launch only: copying the offline speech files. $percent%'
                : 'Loading offline speech. This takes a moment.',
            textAlign: TextAlign.center,
            style: PrepType.meta,
          ),
          const SizedBox(height: Space.m),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(
                value: setup.copying ? setup.progress : null,
                minHeight: 2,
                color: PrepColors.accent,
                backgroundColor: PrepColors.line,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small sheet that says where the coach is and whether it answers.
Future<void> showSettingsSheet(BuildContext context) {
  final services = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: PrepColors.surface1,
    barrierColor: const Color(0xB3000000),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    builder: (context) => _SettingsSheet(services: services),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.services});

  final AppServices services;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late Future<CoachHealth> _health = widget.services.coach.health();

  Future<void> _deletePractice() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete this practice?'),
      content: const Text('This removes your saved job, answers, feedback and interview notes from this device.'),
      actions: [
        QuietButton('Cancel', onPressed: () => Navigator.pop(context, false)),
        QuietButton('Delete', color: PrepColors.danger, onPressed: () => Navigator.pop(context, true)),
      ],
    ));
    if (confirmed != true) return;
    await widget.services.sessions.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      widget.services.sessions.saveFailed ? "Couldn't delete the saved practice. Try again." : 'Saved practice deleted.',
    )));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, Space.x3, 0, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Semantics(header: true, child: Text('Settings', style: PrepType.headline)),
          ),
          const SizedBox(height: Space.l),
          FutureBuilder<CoachHealth>(
            future: _health,
            builder: (context, snap) {
              final String status;
              if (snap.connectionState != ConnectionState.done) {
                status = 'Checking the connection';
              } else if (snap.data?.ok ?? false) {
                status = snap.data!.mock ? 'Connected. The server is giving sample answers, not real AI feedback.' : 'Connected';
              } else {
                status = 'Not reachable. Start the coach server, then check again.';
              }
              return _InfoRow(icon: PrepIcons.compass, title: 'Coach', lines: [
                status,
                if (snap.data?.provider.isNotEmpty ?? false)
                  '${snap.data!.provider} · ${snap.data!.model}${snap.data!.cloud ? ' · cloud AI' : ''}',
                widget.services.coachLabel,
              ]);
            },
          ),
          const Hairline(indent: Space.gutter + 24 + Space.l),
          _InfoRow(icon: PrepIcons.mic, title: 'Voice', lines: [widget.services.speechLabel]),
          const Hairline(indent: Space.gutter + 24 + Space.l),
          LinkRow(
            icon: PrepIcons.shield,
            title: 'Privacy',
            meta: 'What stays on this phone and what is sent.',
            onTap: () => showConsentSheet(context, infoOnly: true),
          ),
          ListenableBuilder(
            listenable: widget.services.sessions,
            builder: (context, _) => widget.services.sessions.last == null && !widget.services.sessions.saveFailed
                ? const SizedBox.shrink()
                : LinkRow(icon: PrepIcons.write, title: 'Delete saved practice',
                    meta: 'Remove your answers, feedback and notes from this device.', onTap: _deletePractice),
          ),
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: PrimaryButton('Check again', onPressed: () => setState(() => _health = widget.services.coach.health())),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.lines});

  final PrepIcons icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrepIcon(icon, color: PrepColors.text2),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PrepType.bodyLMedium),
                for (final line in lines) Text(line, style: PrepType.meta.copyWith(color: PrepColors.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
