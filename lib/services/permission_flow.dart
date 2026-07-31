import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// What a permission request came back with.
enum PermissionOutcome { granted, denied, permanentlyDenied }

/// The permissions a drive needs, in the order they must be asked for.
enum PermissionStep {
  /// Without this there is no speed and no position. Blocking.
  fineLocation,

  /// Android 13+. Without it the foreground-service notification is invisible
  /// and the service looks broken to the user.
  notifications,

  /// Android 11+ will not grant this in the same prompt as fine location, and
  /// Play review requires a documented justification for it.
  backgroundLocation,

  /// Used to measure ambient light. Genuinely optional — the speed model falls
  /// back to solar elevation and weather.
  camera,
}

extension PermissionStepDetail on PermissionStep {
  /// Whether a drive can start at all without this.
  bool get isRequired => this == PermissionStep.fineLocation;

  String get title => switch (this) {
        PermissionStep.fineLocation => 'Location',
        PermissionStep.notifications => 'Notifications',
        PermissionStep.backgroundLocation => 'Location while driving',
        PermissionStep.camera => 'Camera',
      };

  /// Shown before the system prompt, so the user knows what they are agreeing
  /// to and why. Asking cold is the most common reason these get denied.
  String get rationale => switch (this) {
        PermissionStep.fineLocation =>
          'Dynamic Speed needs your location to measure your speed and to know '
              'which road you are on. Nothing works without it.',
        PermissionStep.notifications =>
          'While you are driving, the app shows an ongoing notification with '
              'your current speed and the recommended limit. Android needs your '
              'permission to display it.',
        PermissionStep.backgroundLocation =>
          'Your screen will lock during a drive. To keep monitoring your speed '
              'and warning you about zones, the app needs location access while '
              'it is in the background.\n\nOn the next screen, choose '
              '"Allow all the time".',
        PermissionStep.camera =>
          'The camera measures how bright it is outside, so the app can tell '
              'the difference between daylight and a dark road. You can skip '
              'this — the app will estimate from the time of day and weather '
              'instead.',
      };

  /// What the user loses by saying no. Only meaningful for optional steps.
  String get consequenceIfDenied => switch (this) {
        PermissionStep.fineLocation => 'The app cannot monitor your driving.',
        PermissionStep.notifications =>
          'You will not see the ongoing drive notification.',
        PermissionStep.backgroundLocation =>
          'Monitoring will stop when your screen locks.',
        PermissionStep.camera =>
          'Light levels will be estimated rather than measured.',
      };
}

/// Isolates the platform permission calls so the sequencing logic can be
/// tested without a device.
abstract class PermissionGateway {
  Future<PermissionOutcome> request(PermissionStep step);
  Future<PermissionOutcome> status(PermissionStep step);
  Future<bool> openSettings();
}

class PlatformPermissionGateway implements PermissionGateway {
  const PlatformPermissionGateway();

  Permission _permissionFor(PermissionStep step) => switch (step) {
        PermissionStep.fineLocation => Permission.location,
        PermissionStep.notifications => Permission.notification,
        PermissionStep.backgroundLocation => Permission.locationAlways,
        PermissionStep.camera => Permission.camera,
      };

  PermissionOutcome _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return PermissionOutcome.granted;
    }
    if (status.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    return PermissionOutcome.denied;
  }

  @override
  Future<PermissionOutcome> request(PermissionStep step) async =>
      _map(await _permissionFor(step).request());

  @override
  Future<PermissionOutcome> status(PermissionStep step) async =>
      _map(await _permissionFor(step).status);

  @override
  Future<bool> openSettings() => ph.openAppSettings();
}

/// The outcome of running the whole pre-drive sequence.
class DrivePermissionResult {
  final Map<PermissionStep, PermissionOutcome> outcomes;

  const DrivePermissionResult(this.outcomes);

  bool granted(PermissionStep step) =>
      outcomes[step] == PermissionOutcome.granted;

  /// Whether a drive can start. Only fine location blocks.
  bool get canDrive => granted(PermissionStep.fineLocation);

  /// Whether the drive will survive the screen locking.
  bool get survivesScreenLock =>
      granted(PermissionStep.backgroundLocation) &&
      granted(PermissionStep.notifications);

  /// Optional permissions the user declined, for an honest summary afterwards.
  List<PermissionStep> get declinedOptional => outcomes.entries
      .where((e) => !e.key.isRequired && e.value != PermissionOutcome.granted)
      .map((e) => e.key)
      .toList();
}

/// Asks for the drive permissions one at a time, each behind its own rationale.
///
/// The order matters and is not negotiable: Android 11+ refuses to grant
/// background location in the same prompt as fine location, so it has to be a
/// separate step after fine location is already held. Notifications come in
/// between because without them the foreground-service notification is
/// invisible and the whole thing looks broken.
///
/// Previously the app fired a bare camera request from the Start button with no
/// explanation at all, and never asked for background location or notifications
/// — which is why a locked screen ended the drive.
class PermissionFlow {
  final PermissionGateway _gateway;

  const PermissionFlow({PermissionGateway gateway = const PlatformPermissionGateway()})
      : _gateway = gateway;

  static const List<PermissionStep> driveSequence = [
    PermissionStep.fineLocation,
    PermissionStep.notifications,
    PermissionStep.backgroundLocation,
    PermissionStep.camera,
  ];

  /// Runs the sequence. [showRationale] presents the in-context explanation and
  /// returns false if the user does not want to be asked.
  ///
  /// Stops early only if fine location is refused — everything after it is
  /// optional, and the app should degrade rather than hold the drive hostage.
  Future<DrivePermissionResult> requestForDrive({
    required Future<bool> Function(PermissionStep step) showRationale,
  }) async {
    final outcomes = <PermissionStep, PermissionOutcome>{};

    for (final step in driveSequence) {
      final existing = await _gateway.status(step);
      if (existing == PermissionOutcome.granted) {
        outcomes[step] = existing;
        continue;
      }

      // Re-prompting a permanently denied permission does nothing; the user has
      // to go to Settings. Record it and move on rather than showing a
      // rationale for a dialog that will never appear.
      if (existing == PermissionOutcome.permanentlyDenied) {
        outcomes[step] = existing;
        if (step.isRequired) break;
        continue;
      }

      final proceed = await showRationale(step);
      if (!proceed) {
        outcomes[step] = PermissionOutcome.denied;
        if (step.isRequired) break;
        continue;
      }

      final outcome = await _gateway.request(step);
      outcomes[step] = outcome;

      if (step.isRequired && outcome != PermissionOutcome.granted) break;
    }

    return DrivePermissionResult(outcomes);
  }

  Future<bool> openSettings() => _gateway.openSettings();
}
