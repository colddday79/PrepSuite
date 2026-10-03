import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../design/glass.dart';
import '../../design/icons.dart';
import '../../design/metal.dart';
import '../../design/tokens.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../practice/practice_screen.dart';
import '../profile/profile_screen.dart';
import 'shell_scope.dart';

/// The app's real frame: four tabs kept alive in an [IndexedStack] in one lit room
/// ([AmbientBackdrop], so the glass cards have light behind them), under a floating glass tab bar.
/// The tabs are transparent; content scrolls beneath the bar and each tab pads its list by
/// [floatingTabBarInset].
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _items = [
    TabItem(key: ValueKey('tab-home'), icon: PrepIcons.home, label: 'Home'),
    TabItem(key: ValueKey('tab-practice'), icon: PrepIcons.target, label: 'Practice'),
    TabItem(key: ValueKey('tab-history'), icon: PrepIcons.clock, label: 'History'),
    TabItem(key: ValueKey('tab-profile'), icon: PrepIcons.user, label: 'Profile'),
  ];

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
    // The system inset alone. With extendBody the Scaffold reports the bar's whole height as the
    // body's bottom padding; the tabs add the bar themselves (floatingTabBarInset), so they get
    // the system inset back instead of counting the bar twice.
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    return ShellScope(
      tab: _tab,
      goTo: _goTo,
      child: ListenableBuilder(
        listenable: services.assistant,
        builder: (context, _) {
          return Scaffold(
            backgroundColor: PrepColors.bg,
            extendBody: true,
            body: AmbientBackdrop(
              child: Builder(
                builder: (context) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(padding: media.padding.copyWith(bottom: systemBottom)),
                    child: IndexedStack(
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
                  );
                },
              ),
            ),
            bottomNavigationBar: FloatingTabBar(
              items: _items,
              index: _tab.index,
              onSelect: (i) => _goTo(ShellTab.values[i]),
            ),
          );
        },
      ),
    );
  }
}
