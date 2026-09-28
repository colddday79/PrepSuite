import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/assistant.dart';
import '../../app/services.dart';
import '../../design/assistant_avatar.dart';
import '../../design/assistant_picker.dart';
import '../../design/components.dart';
import '../../design/hologram.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';

const int _pageCount = 7;

/// First-run introduction: who the assistant is, how practising works, choosing a look, a few
/// words about the person, then privacy. A [PageView] moved only by its own buttons (never by a
/// swipe, so "Continue", "Skip", "Agree" and "Not now" are always the ones deciding what happens
/// next), with small dots in the assistant's glow colour and Back wherever there is somewhere to
/// go back to.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pageController = PageController();
  final _welcomeLevel = LevelMix();
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _about = TextEditingController();

  late AppServices _services;
  int _page = 0;
  AssistantMood _welcomeMood = AssistantMood.happy;
  bool _prefilled = false;
  bool _savingProfile = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    // Waits for the first frame, so AppScope (read in didChangeDependencies) is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _welcomeLevel.listenTo(_services.voice.level);
      _speakWelcome();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    // Someone who already told the app their name or role (a repeat run from Settings) sees it
    // again instead of blank fields that would overwrite it on Continue.
    if (!_prefilled) {
      _prefilled = true;
      final profile = _services.profile.value;
      _name.text = profile.name;
      _role.text = profile.targetRole;
      _about.text = profile.about;
    }
  }

  @override
  void dispose() {
    unawaited(_services.voice.stop());
    _pageController.dispose();
    _welcomeLevel.dispose();
    _name.dispose();
    _role.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _speakWelcome() async {
    final look = _services.assistant.value;
    setState(() => _welcomeMood = AssistantMood.speaking);
    try {
      await _services.voice.speak("Hi, I'm ${look.name}. Let's get you ready for your interview.");
    } catch (_) {
      // The greeting is already on screen; a silent assistant isn't a reason to stop.
    }
    _welcomeLevel.rest();
    if (mounted) setState(() => _welcomeMood = AssistantMood.happy);
  }

  void _onPageChanged(int page) {
    if (_page == 0 && page != 0) unawaited(_services.voice.stop());
    setState(() => _page = page);
  }

  void _goTo(int index) {
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      index.clamp(0, _pageCount - 1),
      duration: Motion.enter,
      curve: Motion.standard,
    );
  }

  Future<void> _continueAboutYou() async {
    if (_savingProfile) return;
    setState(() => _savingProfile = true);
    await _services.profile.save(
      _services.profile.value.copyWith(
        name: _name.text.trim(),
        targetRole: _role.text.trim(),
        about: _about.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _savingProfile = false);
    _goTo(6);
  }

  void _skipAboutYou() => _goTo(6);

  Future<void> _agree() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await _services.consent.accept();
    await _services.assistant.finishOnboarding();
    if (!mounted) return;
    widget.onDone();
  }

  Future<void> _notNow() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await _services.assistant.finishOnboarding();
    if (!mounted) return;
    widget.onDone();
  }

  /// The assistant fills about 45% of the screen on the hero moments (Welcome and the picker).
  double get _heroSize => (MediaQuery.sizeOf(context).height * 0.45).clamp(220.0, 420.0);

  /// A touch smaller on the tutorial steps, which sit above one short line rather than a title
  /// and a line.
  double get _stepSize => (MediaQuery.sizeOf(context).height * 0.4).clamp(200.0, 380.0);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistantLook>(
      valueListenable: _services.assistant,
      builder: (context, look, _) {
        return Scaffold(
          backgroundColor: PrepColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                _topBar(look.glow),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    children: [
                      _welcomePage(look),
                      _stepPage(look: look, mood: AssistantMood.listening, title: 'Tell me the job'),
                      _stepPage(look: look, mood: AssistantMood.speaking, title: 'Answer out loud'),
                      _stepPage(look: look, mood: AssistantMood.happy, title: 'Get honest feedback'),
                      _chooseAssistantPage(look),
                      _aboutYouPage(),
                      _privacyPage(look),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topBar(Color glow) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: Space.xs),
          _page > 0
              ? IconAction(PrepIcons.back, label: 'Back', plain: true, onPressed: () => _goTo(_page - 1))
              : const SizedBox(width: 48, height: 48),
          Expanded(child: Center(child: _dots(glow))),
          const SizedBox(width: Space.xs + 48),
        ],
      ),
    );
  }

  Widget _dots(Color glow) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _pageCount; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xxs),
              child: AnimatedContainer(
                duration: Motion.fade,
                curve: Motion.standard,
                width: i == _page ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? glow : PrepColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One scrollable page, so nothing overflows however small the phone or large the text.
  Widget _body(List<Widget> children) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.l, Space.gutter, Space.xxl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _welcomePage(AssistantLook look) {
    return _body([
      Center(
        child: AssistantAvatar(look: look, size: _heroSize, mood: _welcomeMood, level: _welcomeLevel, hud: true),
      ),
      const SizedBox(height: Space.xxl),
      Semantics(
        header: true,
        child: Text("Hi, I'm ${look.name}.", textAlign: TextAlign.center, style: PrepType.display),
      ),
      const SizedBox(height: Space.s),
      Text(
        "Let's get you ready for your interview.",
        textAlign: TextAlign.center,
        style: PrepType.bodyL.copyWith(color: PrepColors.text2),
      ),
      const SizedBox(height: Space.x4),
      PrimaryButton('Start', onPressed: () => _goTo(1)),
    ]);
  }

  Widget _stepPage({required AssistantLook look, required AssistantMood mood, required String title}) {
    return _body([
      Center(child: AssistantAvatar(look: look, size: _stepSize, mood: mood, hud: true)),
      const SizedBox(height: Space.xxl),
      Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: PrepType.display)),
      const SizedBox(height: Space.x4),
      PrimaryButton('Next', onPressed: () => _goTo(_page + 1)),
    ]);
  }

  Widget _chooseAssistantPage(AssistantLook look) {
    return _body([
      Center(child: AssistantAvatar(look: look, size: _heroSize, mood: AssistantMood.happy, hud: true)),
      const SizedBox(height: Space.xxl),
      Semantics(
        header: true,
        child: Text('Choose your assistant', textAlign: TextAlign.center, style: PrepType.display),
      ),
      const SizedBox(height: Space.xxl),
      AssistantPicker(selected: look.kind, onSelected: (kind) => _services.assistant.choose(kind)),
      const SizedBox(height: Space.x4),
      PrimaryButton('Choose ${look.name}', onPressed: () => _goTo(5)),
    ]);
  }

  Widget _aboutYouPage() {
    return _body([
      Semantics(header: true, child: Text('About you', style: PrepType.display)),
      const SizedBox(height: Space.xxl),
      MergeSemantics(
        child: PrepTextField(
          fieldKey: const ValueKey('onboarding-name'),
          label: 'Name',
          controller: _name,
          hint: 'Your first name',
          textInputAction: TextInputAction.next,
        ),
      ),
      const SizedBox(height: Space.l),
      MergeSemantics(
        child: PrepTextField(
          fieldKey: const ValueKey('onboarding-role'),
          label: "Job you're preparing for",
          controller: _role,
          hint: 'For example, junior barista',
          textInputAction: TextInputAction.next,
        ),
      ),
      const SizedBox(height: Space.l),
      MergeSemantics(
        child: PrepTextField(
          fieldKey: const ValueKey('onboarding-about'),
          label: 'About me',
          controller: _about,
          hint: 'A few words about you',
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.done,
        ),
      ),
      const SizedBox(height: Space.x4),
      PrimaryButton('Continue', busy: _savingProfile, onPressed: _continueAboutYou),
      const SizedBox(height: Space.s),
      Center(child: QuietButton('Skip', onPressed: _savingProfile ? null : _skipAboutYou)),
    ]);
  }

  Widget _privacyPage(AssistantLook look) {
    return _body([
      Semantics(header: true, child: Text('Privacy', style: PrepType.display)),
      const SizedBox(height: Space.xxl),
      _PrivacyPoint(icon: PrepIcons.mic, text: 'Your voice becomes text on this phone.', glow: look.glow),
      const SizedBox(height: Space.l),
      _PrivacyPoint(
        icon: PrepIcons.arrowUpRight,
        text: 'Only the text and your pace go to the AI coach.',
        glow: look.glow,
      ),
      const SizedBox(height: Space.l),
      _PrivacyPoint(icon: PrepIcons.lock, text: 'Audio is never uploaded.', glow: look.glow),
      const SizedBox(height: Space.x4),
      PrimaryButton('Agree and start', busy: _finishing, onPressed: _agree),
      const SizedBox(height: Space.s),
      Center(child: QuietButton('Not now', onPressed: _finishing ? null : _notNow)),
    ]);
  }
}

/// One privacy line: a small disc in the assistant's glow colour holding a hairline icon.
class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.icon, required this.text, required this.glow});

  final PrepIcons icon;
  final String text;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(color: glow.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Center(child: PrepIcon(icon, color: glow, size: 20)),
          ),
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(text, style: PrepType.bodyL),
          ),
        ),
      ],
    );
  }
}
