import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design/components.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../practice/practice_screen.dart';
import '../profile/profile_screen.dart';
import 'shell_scope.dart';

/// The app's real frame: four tabs kept alive in an [IndexedStack] and a plain, even tab bar.
/// Starting practice lives on Home and Practice, so the bar carries no floating action.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  ShellTab _tab = ShellTab.home;
  final _visited = <ShellTab>{ShellTab.home};

  void _goTo(ShellTab tab) {
    if (_tab == tab) return;
    setState(() {
      _visited.add(tab);
      _tab = tab;
    });
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
            bottomNavigationBar: _ShellBar(tab: _tab, onSelect: _goTo),
          );
        },
      ),
    );
  }
}

class _ShellBar extends StatelessWidget {
  const _ShellBar({required this.tab, required this.onSelect});

  final ShellTab tab;
  final ValueChanged<ShellTab> onSelect;

  static const double _barHeight = 64;
  static const _tabs = [
    (ShellTab.home, PrepIcons.home, 'Home'),
    (ShellTab.practice, PrepIcons.target, 'Practice'),
    (ShellTab.history, PrepIcons.clock, 'History'),
    (ShellTab.profile, PrepIcons.user, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, box) {
          final tabWidth = box.maxWidth / _tabs.length;
          var labelHeight = 0.0;
          for (final (_, _, label) in _tabs) {
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
          final height = showLabels ? math.max(_barHeight, labelHeight + 40) : _barHeight;
          return Container(
            height: height + bottomInset,
            padding: EdgeInsets.only(bottom: bottomInset),
            decoration: BoxDecoration(
              color: PrepColors.bg,
              border: Border(top: BorderSide(color: PrepColors.line)),
            ),
            child: Row(
              children: [
                for (final (i, (shellTab, icon, label)) in _tabs.indexed)
                  Expanded(
                    child: _TabItem(
                      itemKey: ValueKey('tab-${shellTab.name}'),
                      icon: icon,
                      label: label,
                      showLabel: showLabels,
                      index: i,
                      selected: tab == shellTab,
                      onTap: () => onSelect(shellTab),
                    ),
                  ),
              ],
            ),
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
    required this.onTap,
  });

  final Key itemKey;
  final PrepIcons icon;
  final String label;
  final bool showLabel;
  final int index;
  final bool selected;
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
                      color: PrepColors.accent,
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
