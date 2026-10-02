import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../consent/consent_sheet.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../intake/intake_screen.dart';
import '../practice/practice_screen.dart';
import '../profile/profile_screen.dart';
import 'shell_scope.dart';

/// The app's real frame: four tabs kept alive in an [IndexedStack], with a raised centre button
/// that jumps straight into a mock interview from anywhere.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  ShellTab _tab = ShellTab.home;
  final _visited = <ShellTab>{ShellTab.home};
  bool _starting = false;

  void _goTo(ShellTab tab) {
    if (_tab == tab) return;
    setState(() {
      _visited.add(tab);
      _tab = tab;
    });
  }

  Future<bool> _ensureConsent() async {
    final services = AppScope.of(context);
    if (await services.consent.accepted()) return true;
    if (!mounted) return false;
    if (!await showConsentSheet(context)) return false;
    await services.consent.accept();
    return true;
  }

  Future<void> _startMockInterview() async {
    if (_starting) return;
    _starting = true;
    try {
      if (!await _ensureConsent() || !mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const IntakeScreen()));
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ShellScope(
      tab: _tab,
      goTo: _goTo,
      child: ListenableBuilder(
        listenable: services.assistant,
        builder: (context, _) {
          final glow = services.assistant.value.tone;
          return Scaffold(
            backgroundColor: PrepColors.bg,
            body: IndexedStack(
              index: _tab.index,
              children: [
                for (final tab in ShellTab.values)
                  TickerMode(
                    enabled: tab == _tab,
                    child: _visited.contains(tab)
                        ? switch (tab) {
                            ShellTab.home => const HomeScreen(),
                            ShellTab.practice => const PracticeScreen(),
                            ShellTab.history => const HistoryScreen(),
                            ShellTab.profile => const ProfileScreen(),
                          }
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
            bottomNavigationBar: _ShellBar(
              tab: _tab,
              onSelect: _goTo,
              onCentre: _startMockInterview,
              glow: glow,
            ),
          );
        },
      ),
    );
  }
}

class _ShellBar extends StatelessWidget {
  const _ShellBar({
    required this.tab,
    required this.onSelect,
    required this.onCentre,
    required this.glow,
  });

  final ShellTab tab;
  final ValueChanged<ShellTab> onSelect;
  final VoidCallback onCentre;
  final Color glow;

  static const double _barHeight = 64;
  static const double _centreSize = 64;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, box) {
          final centreGap = math.min(
            _centreSize + Space.m,
            box.maxWidth * 0.24,
          );
          final tabWidth = (box.maxWidth - centreGap) / 4;
          var labelHeight = 0.0;
          for (final label in ['Home', 'Practice', 'History', 'Profile']) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: PrepType.caption),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: tabWidth);
            labelHeight = math.max(labelHeight, painter.height);
            painter.dispose();
          }
          // Keep enlarged labels from consuming the screen on a narrow phone.
          // Compact tabs retain their full names through tooltips and semantics.
          final showLabels = labelHeight <= 56;
          final height = showLabels
              ? math.max(_barHeight, labelHeight + 40)
              : _barHeight;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                height: height + bottomInset,
                padding: EdgeInsets.only(bottom: bottomInset),
                decoration: const BoxDecoration(
                  color: PrepColors.surface1,
                  border: Border(top: BorderSide(color: PrepColors.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _TabItem(
                        itemKey: const ValueKey('tab-home'),
                        icon: PrepIcons.home,
                        label: 'Home',
                        showLabel: showLabels,
                        index: 0,
                        selected: tab == ShellTab.home,
                        glow: glow,
                        onTap: () => onSelect(ShellTab.home),
                      ),
                    ),
                    Expanded(
                      child: _TabItem(
                        itemKey: const ValueKey('tab-practice'),
                        icon: PrepIcons.target,
                        label: 'Practice',
                        showLabel: showLabels,
                        index: 1,
                        selected: tab == ShellTab.practice,
                        glow: glow,
                        onTap: () => onSelect(ShellTab.practice),
                      ),
                    ),
                    SizedBox(width: centreGap),
                    Expanded(
                      child: _TabItem(
                        itemKey: const ValueKey('tab-history'),
                        icon: PrepIcons.clock,
                        label: 'History',
                        showLabel: showLabels,
                        index: 2,
                        selected: tab == ShellTab.history,
                        glow: glow,
                        onTap: () => onSelect(ShellTab.history),
                      ),
                    ),
                    Expanded(
                      child: _TabItem(
                        itemKey: const ValueKey('tab-profile'),
                        icon: PrepIcons.user,
                        label: 'Profile',
                        showLabel: showLabels,
                        index: 3,
                        selected: tab == ShellTab.profile,
                        glow: glow,
                        onTap: () => onSelect(ShellTab.profile),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -_centreSize * 0.44,
                child: _CentreButton(glow: glow, onTap: onCentre),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.index,
    required this.selected,
    required this.glow,
    required this.onTap,
  });

  final Key itemKey;
  final PrepIcons icon;
  final String label;
  final bool showLabel;
  final int index;
  final bool selected;
  final Color glow;
  final VoidCallback onTap;

  static const int _total = 4;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PrepColors.text : PrepColors.text3;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '$label, tab ${index + 1} of $_total',
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: FocusRing(
          gap: -Space.xs,
          child: InkWell(
            key: itemKey,
            onTap: onTap,
            focusColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: Motion.fade,
                    curve: Motion.standard,
                    width: selected ? 20 : 0,
                    height: 4,
                    decoration: BoxDecoration(
                      color: glow,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  PrepIcon(icon, color: color, size: 22),
                  if (showLabel) ...[
                    const SizedBox(height: Space.xxs),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: PrepType.caption.copyWith(color: color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CentreButton extends StatelessWidget {
  const _CentreButton({required this.glow, required this.onTap});

  final Color glow;
  final VoidCallback onTap;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start a mock interview',
      onTap: onTap,
      excludeSemantics: true,
      child: FocusRing(
        radius: _size / 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.45),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: glow,
            shape: const CircleBorder(),
            child: InkWell(
              key: const ValueKey('shell-centre-button'),
              onTap: onTap,
              customBorder: const CircleBorder(),
              focusColor: Colors.transparent,
              highlightColor: PrepColors.bg.withValues(alpha: 0.12),
              child: const SizedBox.square(
                dimension: _size,
                child: Center(
                  child: PrepIcon(
                    PrepIcons.mic,
                    color: PrepColors.bg,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
