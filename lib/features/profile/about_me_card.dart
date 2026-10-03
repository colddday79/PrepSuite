import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../coach/contracts.dart';
import '../../coach/speech_adapter.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import '../common/coach_widgets.dart';

/// How long a "Say it" recording can run before it stops itself.
const _maxAbout = Duration(seconds: 60);

/// The centre of the Profile page: how the person describes themselves, with a typed edit and a
/// spoken one. Empty shows one line and the two actions; filled shows the text itself.
class AboutMeCard extends StatelessWidget {
  const AboutMeCard({super.key, required this.about, required this.onEdit, required this.onSayIt});

  final String about;
  final VoidCallback onEdit;
  final VoidCallback onSayIt;

  @override
  Widget build(BuildContext context) {
    final empty = about.trim().isEmpty;
    return MetalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('About me', style: PrepType.titleM)),
          const SizedBox(height: Space.m),
          Text(
            empty ? 'Describe yourself in a few sentences.' : about,
            style: empty ? PrepType.bodyL.copyWith(color: PrepColors.text3) : PrepType.bodyL,
          ),
          const SizedBox(height: Space.m),
          // The buttons pad their labels by 12; pull them back so the labels line up with the text.
          Transform.translate(
            offset: const Offset(-Space.m, 0),
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.xs,
              children: [
                QuietButton('Edit', icon: PrepIcons.edit, onPressed: onEdit),
                QuietButton('Say it', icon: PrepIcons.mic, onPressed: onSayIt),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a sheet with a large text field for [Profile.about]. Saves only when the person taps
/// Save.
Future<void> showEditAboutSheet(BuildContext context) async {
  final services = AppScope.of(context);
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PrepColors.surface1,
    barrierColor: PrepColors.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _EditAboutSheet(initial: services.profile.value.about),
    ),
  );
  if (result != null) {
    final profile = services.profile;
    profile.save(profile.value.copyWith(about: result));
  }
}

/// Owns its own controller so it is disposed only once this sheet itself leaves the tree (after
/// its closing animation), never by the caller that awaited it.
class _EditAboutSheet extends StatefulWidget {
  const _EditAboutSheet({required this.initial});

  final String initial;

  @override
  State<_EditAboutSheet> createState() => _EditAboutSheetState();
}

class _EditAboutSheetState extends State<_EditAboutSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xxl, Space.x3, Space.xxl, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(header: true, child: Text('About me', style: PrepType.headline)),
          const SizedBox(height: Space.xl),
          PrepTextField(
            fieldKey: const ValueKey('about-field'),
            controller: _controller,
            hint: 'Describe yourself in a few sentences.',
            minLines: 6,
            maxLines: 14,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: Space.xl),
          PrimaryButton('Save', onPressed: () => Navigator.of(context).pop(_controller.text.trim())),
        ],
      ),
    );
  }
}

/// Opens a sheet that records up to 60 seconds and adds the transcript to [Profile.about]:
/// replacing it if it was empty, otherwise appending it as a new paragraph.
Future<void> showSayItSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PrepColors.surface1,
    barrierColor: PrepColors.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    builder: (context) => const _SayItSheet(),
  );
}

enum _SayPhase { ready, preparing, recording, transcribing, unheard, micOff }

class _SayItSheet extends StatefulWidget {
  const _SayItSheet();

  @override
  State<_SayItSheet> createState() => _SayItSheetState();
}

class _SayItSheetState extends State<_SayItSheet> {
  late AppServices _services;
  bool _wired = false;
  final _progress = ValueNotifier<double>(0);
  StreamSubscription<String>? _partialSub;
  Timer? _ticker;
  _SayPhase _phase = _SayPhase.ready;
  String _partial = '';
  bool _micBlocked = false;
  bool _micFailed = false;
  String? _speechError;
  int _operation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    if (!_wired) {
      _wired = true;
      _partialSub = _services.speech.partialText.listen((text) {
        if (mounted && _phase == _SayPhase.recording) setState(() => _partial = text);
      });
    }
  }

  @override
  void dispose() {
    _operation++;
    _ticker?.cancel();
    _partialSub?.cancel();
    if (_phase == _SayPhase.recording || _phase == _SayPhase.preparing) {
      _services.speech.cancel();
    }
    _progress.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    if (_phase == _SayPhase.recording) return _stop();
    if (_phase == _SayPhase.preparing || _phase == _SayPhase.transcribing) return;
    final operation = ++_operation;
    setState(() {
      _phase = _SayPhase.preparing;
      _speechError = null;
    });
    try {
      final access = await _services.mic.request();
      if (!mounted || operation != _operation) return;
      if (access != MicAccess.granted) {
        setState(() {
          _micBlocked = access == MicAccess.blocked;
          _micFailed = false;
          _phase = _SayPhase.micOff;
        });
        return;
      }
      final started = await _services.speech.start(maxDuration: _maxAbout);
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
        _phase = _SayPhase.micOff;
      });
      return;
    }
    _progress.value = 0;
    var elapsed = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed += 100;
      _progress.value = elapsed / _maxAbout.inMilliseconds;
      if (elapsed >= _maxAbout.inMilliseconds) _stop();
    });
    setState(() {
      _partial = '';
      _phase = _SayPhase.recording;
    });
  }

  Future<void> _stop() async {
    if (_phase != _SayPhase.recording) return;
    _ticker?.cancel();
    setState(() => _phase = _SayPhase.transcribing);
    CaptureResult? result;
    try {
      result = await _services.speech.stop();
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    final heard = result?.transcript.text.trim() ?? '';
    if (heard.isEmpty) {
      setState(() => _phase = _SayPhase.unheard);
      return;
    }
    final profile = _services.profile;
    final current = profile.value.about.trim();
    profile.save(profile.value.copyWith(about: current.isEmpty ? heard : '$current\n\n$heard'));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xxl, Space.x3, Space.xxl, Space.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Say it', style: PrepType.headline, textAlign: TextAlign.center),
          ),
          const SizedBox(height: Space.xxl),
          ..._content(),
        ],
      ),
    );
  }

  List<Widget> _content() {
    switch (_phase) {
      case _SayPhase.ready:
      case _SayPhase.preparing:
      case _SayPhase.recording:
        final recording = _phase == _SayPhase.recording;
        return [
          Center(
            child: RecordButton(
              recording: recording,
              progress: _progress,
              onPressed: _phase == _SayPhase.preparing ? null : _record,
            ),
          ),
          const SizedBox(height: Space.l),
          Center(
            child: Text(
              recording ? (_partial.isEmpty ? 'Listening' : _partial) : 'Up to 60 seconds',
              textAlign: TextAlign.center,
              style: PrepType.bodyL.copyWith(
                color: recording && _partial.isNotEmpty ? PrepColors.text : PrepColors.text3,
              ),
            ),
          ),
        ];
      case _SayPhase.transcribing:
        return const [LoadingLine('Turning your voice into text')];
      case _SayPhase.unheard:
        return [
          const ProblemNote(title: "We couldn't hear that.", body: 'Try again.'),
          const SizedBox(height: Space.xl),
          Center(
            child: RecordButton(recording: false, progress: _progress, onPressed: _record),
          ),
        ];
      case _SayPhase.micOff:
        return [
          ProblemNote(
            title: _micFailed ? "The microphone didn't start." : 'The microphone is off.',
            body: _micFailed
                ? (_speechError ?? 'Try again.')
                : (_micBlocked ? 'Allow it in Settings.' : 'Allow it when you try again.'),
          ),
          const SizedBox(height: Space.xl),
          Center(
            child: _micBlocked
                ? QuietButton('Open settings', onPressed: _services.mic.openSettings)
                : QuietButton('Try again', onPressed: _record),
          ),
        ];
    }
  }
}
