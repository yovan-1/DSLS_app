import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake while a drive is running.
///
/// Independent of the foreground service and solving a different problem: the
/// foreground service covers the phone in a pocket, this covers the phone in a
/// cradle, where a driver glancing at the speedometer needs it to still be lit.
///
/// Behind an interface for the same reason as [DriveForegroundService] — the
/// coordinator has to run with no Flutter binding.
abstract class ScreenWakeController {
  /// Whether the user wants the screen held awake at all.
  bool get enabled;
  set enabled(bool value);

  /// Called when the session starts or stops, and on foreground/background
  /// transitions. The wakelock is only meaningful while the app is visible.
  Future<void> apply({required bool sessionActive, required bool foregrounded});

  Future<void> release();
}

class NoopScreenWakeController implements ScreenWakeController {
  @override
  bool enabled = true;

  @override
  Future<void> apply({
    required bool sessionActive,
    required bool foregrounded,
  }) async {}

  @override
  Future<void> release() async {}
}

class PlatformScreenWakeController implements ScreenWakeController {
  @override
  bool enabled;

  bool _held = false;

  PlatformScreenWakeController({this.enabled = true});

  @override
  Future<void> apply({
    required bool sessionActive,
    required bool foregrounded,
  }) async {
    // Backgrounded, the wakelock would hold the screen on for an app the user
    // cannot see — a battery drain with no benefit. The foreground service is
    // what keeps the drive alive there.
    final shouldHold = enabled && sessionActive && foregrounded;
    if (shouldHold == _held) return;
    _held = shouldHold;
    await WakelockPlus.toggle(enable: shouldHold);
  }

  @override
  Future<void> release() async {
    if (!_held) return;
    _held = false;
    await WakelockPlus.disable();
  }
}
