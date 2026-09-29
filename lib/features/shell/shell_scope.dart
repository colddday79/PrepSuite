import 'package:flutter/widgets.dart';

/// The four root destinations in [AppShell]'s bottom bar (kept apart from app_shell.dart so
/// screens that only need to switch tabs, such as Home, never have to import the shell itself).
enum ShellTab { home, practice, history, profile }

/// Lets any screen inside the shell switch tabs, for example Home linking to Profile to add an
/// interview date, or History linking to Practice.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.tab, required this.goTo, required super.child});

  final ShellTab tab;
  final ValueChanged<ShellTab> goTo;

  static ShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope missing above $context');
    return scope!;
  }

  @override
  bool updateShouldNotify(ShellScope oldWidget) => tab != oldWidget.tab || goTo != oldWidget.goTo;
}
