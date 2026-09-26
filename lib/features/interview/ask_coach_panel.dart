import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../coach/coach_api.dart';
import '../../coach/contracts.dart';
import '../../coach/speech_adapter.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';
import 'read_aloud.dart';

/// The longest spoken question to the coach.
const askMaxRecording = Duration(seconds: 15);

enum AskStage { closed, ready, preparing, recording, transcribing, unheard, micOff, typing, thinking, answered, error }

/// What the coach is told alongside the person's own question.
class AskTopic {
  const AskTopic({required this.job, this.question = '', this.answer = '', this.feedback});

  final String job;
  final String question;
  final String answer;
  final AnswerFeedback? feedback;
}

/// The person asks the coach a question of their own, out loud (up to 15 seconds) or typed, and
/// Norman reads the answer. The interview screen owns this: it closes it when the person moves
/// on and pauses it with the app, so no microphone or voice outlives the question it was for.
class AskCoachController extends ChangeNotifier {
  AskCoachController({required AppServices services, required ReadAloud voice, required this.preferTyping, required this.mayReadAloud})
      : _services = services,
        // ignore: prefer_initializing_formals
        _voice = voice {
    _partialSub = services.speech.partialText.listen((text) {
      if (_stage != AskStage.recording) return;
      partial = text;
      _notify();
    });
  }

  final AppServices _services;
  final ReadAloud _voice;
  final bool preferTyping;

  /// Whether Norman may read an answer out without being asked (a spoken session, in the foreground).
  final bool Function() mayReadAloud;

  final typed = TextEditingController();
  final progress = ValueNotifier<double>(0);
  StreamSubscription<String>? _partialSub;
  Timer? _ticker;
  int _operation = 0;
  bool _disposed = false;
  bool _typedLast = false;
  AskTopic? _topic;
  AskStage _stage = AskStage.closed;

  String partial = '';
  String asked = '';
  CoachReply? reply;
  CoachException? error;
  bool micBlocked = false;
  bool micFailed = false;
  String? speechError;

  AskStage get stage => _stage;
  bool get isOpen => _stage != AskStage.closed;

  /// The microphone is in use (or about to be), so nothing should be read aloud.
  bool get usingMic => _stage == AskStage.preparing || _stage == AskStage.recording || _stage == AskStage.transcribing;

  /// False on a phone where offline speech could not start; typing still works.
  bool get voiceAvailable => !_services.speechSetup.state.value.isFailed;

  bool get readingReply => _voice.current == Spoken.reply;

  AskStage get _inputStage => preferTyping || _typedLast || !voiceAvailable ? AskStage.typing : AskStage.ready;

  void open(AskTopic topic) {
    _topic = topic;
    _operation++;
    _clear();
    _go(_inputStage);
  }

  /// Closes the panel and drops whatever is in flight: a recording, a pending answer, or the
  /// answer being read out.
  void close() {
    if (_stage == AskStage.closed) return;
    _release();
    if (readingReply) unawaited(_voice.hush());
    _clear();
    typed.clear();
    _go(AskStage.closed);
  }

  /// The app went to the background: a question being recorded is dropped rather than sent.
  void pause() {
    if (_stage != AskStage.preparing && _stage != AskStage.recording) return;
    _release();
    _go(AskStage.ready);
  }

  Future<void> record() async {
    if (_stage == AskStage.recording) return stop();
    if (!isOpen || usingMic || _stage == AskStage.thinking) return;
    final operation = ++_operation;
    speechError = null;
    _go(AskStage.preparing);
    try {
      await _voice.hush();
      if (operation != _operation) return;
      final access = await _services.mic.request();
      if (operation != _operation) return;
      if (access != MicAccess.granted) {
        micBlocked = access == MicAccess.blocked;
        micFailed = false;
        _go(AskStage.micOff);
        return;
      }
      final started = await _services.speech.start(maxDuration: askMaxRecording);
      if (operation != _operation) {
        if (started) await _services.speech.cancel();
        return;
      }
      if (!started) throw StateError('Speech capture could not start');
    } catch (_) {
      if (operation != _operation) return;
      micBlocked = false;
      micFailed = true;
      speechError = speechErrorMessage(_services.speech);
      _go(AskStage.micOff);
      return;
    }
    var elapsed = 0;
    progress.value = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed += 100;
      progress.value = elapsed / askMaxRecording.inMilliseconds;
      if (elapsed >= askMaxRecording.inMilliseconds) stop();
    });
    partial = '';
    _typedLast = false;
    _go(AskStage.recording);
  }

  Future<void> stop() async {
    if (_stage != AskStage.recording) return;
    final operation = _operation;
    _ticker?.cancel();
    _go(AskStage.transcribing);
    CaptureResult? result;
    try {
      result = await _services.speech.stop();
    } catch (_) {
      result = null;
    }
    if (operation != _operation) return;
    final heard = result?.transcript.text.trim() ?? '';
    if (heard.isEmpty) {
      _go(AskStage.unheard);
      return;
    }
    await _send(heard);
  }

  void typeInstead() {
    if (usingMic) _release();
    _typedLast = true;
    _go(AskStage.typing);
  }

  Future<void> sendTyped() async {
    final text = typed.text.trim();
    if (text.isEmpty || _stage != AskStage.typing) return;
    typed.clear();
    _typedLast = true;
    await _send(text);
  }

  Future<void> retry() => _send(asked);

  void askAnother() {
    if (readingReply) unawaited(_voice.hush());
    _operation++;
    _clear();
    _go(_inputStage);
  }

  void toggleReply() {
    if (readingReply) {
      unawaited(_voice.hush());
      return;
    }
    final answer = reply?.answer ?? '';
    if (answer.isEmpty || usingMic) return;
    unawaited(_voice.say(Spoken.reply, speakable(answer)));
  }

  Future<void> openSettings() => _services.mic.openSettings();

  Future<void> _send(String text) async {
    final topic = _topic;
    if (topic == null || text.isEmpty) return;
    final operation = ++_operation;
    asked = text;
    reply = null;
    error = null;
    _go(AskStage.thinking);
    try {
      final answer = await _services.coach.ask(
        job: topic.job,
        userQuestion: text,
        question: topic.question,
        answer: topic.answer,
        feedback: topic.feedback,
      );
      if (operation != _operation) return;
      reply = answer;
      _go(AskStage.answered);
      if (mayReadAloud()) unawaited(_voice.say(Spoken.reply, speakable(answer.answer)));
    } on CoachException catch (e) {
      if (operation != _operation) return;
      error = e;
      _go(AskStage.error);
    } catch (e) {
      if (operation != _operation) return;
      error = CoachException(CoachErrorKind.badResponse, message: '$e');
      _go(AskStage.error);
    }
  }

  /// Makes every late completion stale, and frees the microphone if it was taken.
  void _release() {
    final mic = usingMic;
    _operation++;
    _ticker?.cancel();
    if (mic) unawaited(_services.speech.cancel());
  }

  void _clear() {
    partial = '';
    asked = '';
    reply = null;
    error = null;
    micBlocked = false;
    micFailed = false;
    speechError = null;
    progress.value = 0;
  }

  void _go(AskStage stage) {
    _stage = stage;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    _ticker?.cancel();
    _partialSub?.cancel();
    typed.dispose();
    progress.dispose();
    super.dispose();
  }
}

/// Inline under the feedback: their question in their words, then the coach's answer. Every
/// action here is quiet; "Next question" stays the one primary action on the screen.
class AskCoachPanel extends StatelessWidget {
  const AskCoachPanel({super.key, required this.controller, required this.voice});

  final AskCoachController controller;
  final ReadAloud voice;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, voice]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Hairline(),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Ask the coach', style: PrepType.label.copyWith(color: PrepColors.text2)),
                ),
              ),
              QuietButton('Close', onPressed: controller.close),
            ],
          ),
          const SizedBox(height: Space.xs),
          ..._content(context),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final c = controller;
    switch (c.stage) {
      case AskStage.closed:
        return const [];
      // Ready and recording share one layout, so the record button never moves under a finger.
      case AskStage.ready:
      case AskStage.recording:
        final recording = c.stage == AskStage.recording;
        return [
          const SizedBox(height: Space.s),
          Center(
            child: RecordButton(recording: recording, countdown: true, progress: c.progress, onPressed: c.record),
          ),
          const SizedBox(height: Space.m),
          Center(
            child: recording
                ? ValueListenableBuilder<double>(
                    valueListenable: c.progress,
                    builder: (context, p, _) {
                      final left = ((1 - p.clamp(0.0, 1.0)) * askMaxRecording.inSeconds).ceil();
                      return Text('${left}s left', style: PrepType.meta);
                    },
                  )
                : Text('15 seconds', style: PrepType.meta),
          ),
          const SizedBox(height: Space.s),
          if (recording)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Text(
                c.partial.isEmpty ? 'Listening' : c.partial,
                textAlign: TextAlign.center,
                style: PrepType.bodyL.copyWith(color: c.partial.isEmpty ? PrepColors.text3 : PrepColors.text2),
              ),
            )
          else
            Center(child: QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: c.typeInstead)),
        ];
      case AskStage.preparing:
        return const [SizedBox(height: Space.s), LoadingLine('Preparing microphone')];
      case AskStage.transcribing:
        return const [SizedBox(height: Space.s), LoadingLine('Turning your question into text')];
      case AskStage.unheard:
        return [
          const ProblemNote(
            title: "We couldn't hear your question.",
            body: 'Speak up, or type it.',
          ),
          const SizedBox(height: Space.l),
          Center(child: RecordButton(recording: false, countdown: true, progress: c.progress, onPressed: c.record)),
          const SizedBox(height: Space.s),
          Center(child: QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: c.typeInstead)),
        ];
      case AskStage.micOff:
        return [
          ProblemNote(
            title: c.micFailed ? "The microphone didn't start." : 'The microphone is off.',
            body: c.micFailed
                ? c.speechError ?? 'Try again, or type it.'
                : c.micBlocked
                    ? 'Allow it in Settings, or type it.'
                    : 'Allow it when you try again, or type it.',
          ),
          const SizedBox(height: Space.s),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              QuietButton('Type instead', icon: PrepIcons.keyboard, onPressed: c.typeInstead),
              QuietButton(c.micBlocked ? 'Open settings' : 'Try again', onPressed: c.micBlocked ? c.openSettings : c.record),
            ],
          ),
        ];
      case AskStage.typing:
        void send() {
          FocusScope.of(context).unfocus();
          c.sendTyped();
        }
        return [
          PrepTextField(
            fieldKey: const ValueKey('ask-field'),
            controller: c.typed,
            hint: 'For example: how long should this answer be?',
            minLines: 2,
            maxLines: 5,
            autofocus: true,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => send(),
          ),
          const SizedBox(height: Space.s),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: c.typed,
            builder: (context, value, _) => Wrap(
              alignment: WrapAlignment.center,
              children: [
                QuietButton('Send question', icon: PrepIcons.chat, onPressed: value.text.trim().isEmpty ? null : send),
                if (c.voiceAvailable) QuietButton('Ask out loud instead', icon: PrepIcons.mic, onPressed: c.record),
              ],
            ),
          ),
        ];
      case AskStage.thinking:
        return [
          _Asked(c.asked),
          const SizedBox(height: Space.l),
          const LoadingLine('The coach is thinking'),
        ];
      case AskStage.answered:
        final reply = c.reply!;
        return [
          _Asked(c.asked),
          const SizedBox(height: Space.m),
          if (reply.mock) ...[
            Text('Sample answer', style: PrepType.label.copyWith(color: PrepColors.accent)),
            const SizedBox(height: Space.xs),
          ],
          Semantics(liveRegion: true, child: Text(stripQuotes(reply.answer), style: PrepType.bodyL)),
          const SizedBox(height: Space.s),
          _Actions([
            if (c.voiceAvailable)
              ReadAloudButton(
                label: 'Hear answer',
                stopLabel: 'Stop reading the answer',
                speaking: c.readingReply,
                onPressed: c.toggleReply,
              ),
            QuietButton('Ask another', icon: PrepIcons.chat, onPressed: c.askAnother),
          ]),
        ];
      case AskStage.error:
        return [
          _Asked(c.asked),
          const SizedBox(height: Space.m),
          ProblemNote(title: "Couldn't get an answer.", body: c.error?.userMessage ?? 'Something went wrong. Try again.'),
          const SizedBox(height: Space.s),
          _Actions([
            QuietButton('Try again', icon: PrepIcons.replay, onPressed: c.retry),
            QuietButton('Ask something else', onPressed: c.askAnother),
          ]),
        ];
    }
  }
}

/// Their question, in their words, as a quiet quote.
class _Asked extends StatelessWidget {
  const _Asked(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'You asked: $text',
      excludeSemantics: true,
      child: Text('“$text”', style: PrepType.quote.copyWith(color: PrepColors.text2)),
    );
  }
}

/// Quiet actions under a piece of text, lined up with the text's left edge.
class _Actions extends StatelessWidget {
  const _Actions(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-Space.m, 0),
      child: Wrap(children: children),
    );
  }
}
