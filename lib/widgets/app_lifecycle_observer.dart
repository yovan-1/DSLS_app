import 'package:flutter/widgets.dart';

/// Forwards app lifecycle transitions to plain callbacks.
///
/// The driving coordinator deliberately knows nothing about `WidgetsBinding` —
/// it has to run with no widget tree, which is the whole point of moving the
/// session out of the screen. This widget is the one place that touches the
/// binding, and it hands the coordinator ordinary method calls.
class AppLifecycleObserver extends StatefulWidget {
  final Future<void> Function() onPaused;
  final Future<void> Function() onResumed;
  final Widget child;

  const AppLifecycleObserver({
    super.key,
    required this.onPaused,
    required this.onResumed,
    required this.child,
  });

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        widget.onPaused();
      case AppLifecycleState.resumed:
        widget.onResumed();
      case AppLifecycleState.inactive:
        // Transient — a notification shade pull or an incoming call banner.
        // Tearing the camera down here would thrash it.
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
