import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the drive alive when the screen locks or the app is backgrounded.
///
/// Behind an interface because [DrivingSessionCoordinator] must keep running
/// with no Flutter binding — the platform channels this touches would make the
/// session untestable headlessly, which is precisely the property the whole
/// phase exists to establish.
abstract class DriveForegroundService {
  Future<void> start({required String title, required String text});
  Future<void> update({required String title, required String text});
  Future<void> stop();
}

/// Used in tests and on platforms where there is nothing to keep alive.
class NoopDriveForegroundService implements DriveForegroundService {
  const NoopDriveForegroundService();

  @override
  Future<void> start({required String title, required String text}) async {}

  @override
  Future<void> update({required String title, required String text}) async {}

  @override
  Future<void> stop() async {}
}

/// The callback must be a top-level function — the plugin looks it up by
/// entry-point name when the service starts.
@pragma('vm:entry-point')
void driveTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_DriveTaskHandler());
}

/// Deliberately does nothing.
///
/// The service exists to stop Android trimming the process, not to run the
/// drive. The coordinator keeps running in the main isolate with all its state
/// intact; moving it into the plugin's background isolate would mean
/// duplicating eight services and marshalling everything back over
/// `sendDataToMain` — a rewrite that buys nothing here.
class _DriveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class PlatformDriveForegroundService implements DriveForegroundService {
  static const int _serviceId = 4271;

  bool _initialised = false;

  void _ensureInitialised() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'dsls_drive',
        channelName: 'Drive monitoring',
        channelDescription:
            'Shown while Dynamic Speed is monitoring a drive.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The coordinator drives itself off the GPS stream; the service only
        // needs to hold the process open, so the repeat event is slow.
        eventAction: ForegroundTaskEventAction.repeat(60000),
        // A drive is started deliberately by the user. Resurrecting it on boot
        // would start monitoring nobody asked for.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialised = true;
  }

  @override
  Future<void> start({required String title, required String text}) async {
    _ensureInitialised();
    if (await FlutterForegroundTask.isRunningService) {
      await update(title: title, text: text);
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: title,
      notificationText: text,
      callback: driveTaskCallback,
    );
  }

  @override
  Future<void> update({required String title, required String text}) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  @override
  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}
