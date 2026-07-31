import 'package:dsls_app/services/permission_flow.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGateway implements PermissionGateway {
  final Map<PermissionStep, PermissionOutcome> initialStatus;
  final Map<PermissionStep, PermissionOutcome> requestResult;

  final List<PermissionStep> requested = [];
  int settingsOpened = 0;

  FakeGateway({
    this.initialStatus = const {},
    this.requestResult = const {},
  });

  @override
  Future<PermissionOutcome> status(PermissionStep step) async =>
      initialStatus[step] ?? PermissionOutcome.denied;

  @override
  Future<PermissionOutcome> request(PermissionStep step) async {
    requested.add(step);
    return requestResult[step] ?? PermissionOutcome.granted;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

void main() {
  /// Records which steps were explained, and answers yes to all of them.
  ({List<PermissionStep> shown, Future<bool> Function(PermissionStep) fn})
      acceptAll() {
    final shown = <PermissionStep>[];
    return (
      shown: shown,
      fn: (PermissionStep step) async {
        shown.add(step);
        return true;
      },
    );
  }

  group('sequencing', () {
    test('asks in the order Android requires', () async {
      final gateway = FakeGateway();
      final rationale = acceptAll();

      await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(gateway.requested, [
        PermissionStep.fineLocation,
        PermissionStep.notifications,
        PermissionStep.backgroundLocation,
        PermissionStep.camera,
      ]);
    });

    test('background location is a separate step after fine location', () async {
      final gateway = FakeGateway();
      final rationale = acceptAll();

      await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      final fine = gateway.requested.indexOf(PermissionStep.fineLocation);
      final background =
          gateway.requested.indexOf(PermissionStep.backgroundLocation);
      expect(background, greaterThan(fine),
          reason: 'Android 11+ will not grant these in one prompt');
    });

    test('every step gets its own rationale first', () async {
      final gateway = FakeGateway();
      final rationale = acceptAll();

      await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(rationale.shown, PermissionFlow.driveSequence,
          reason: 'a cold prompt is the main reason these get denied');
    });

    test('does not re-ask for something already granted', () async {
      final gateway = FakeGateway(initialStatus: {
        PermissionStep.fineLocation: PermissionOutcome.granted,
        PermissionStep.notifications: PermissionOutcome.granted,
      });
      final rationale = acceptAll();

      await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(gateway.requested, [
        PermissionStep.backgroundLocation,
        PermissionStep.camera,
      ]);
      expect(rationale.shown, isNot(contains(PermissionStep.fineLocation)));
    });

    test('skips a permanently denied step without a pointless rationale',
        () async {
      final gateway = FakeGateway(initialStatus: {
        PermissionStep.notifications: PermissionOutcome.permanentlyDenied,
      });
      final rationale = acceptAll();

      final result = await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(rationale.shown, isNot(contains(PermissionStep.notifications)),
          reason: 'the system prompt would never appear');
      expect(gateway.requested, isNot(contains(PermissionStep.notifications)));
      expect(result.granted(PermissionStep.notifications), isFalse);
    });
  });

  group('only fine location blocks', () {
    test('refusing fine location stops the sequence', () async {
      final gateway = FakeGateway(requestResult: {
        PermissionStep.fineLocation: PermissionOutcome.denied,
      });
      final rationale = acceptAll();

      final result = await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(result.canDrive, isFalse);
      expect(gateway.requested, [PermissionStep.fineLocation],
          reason: 'nothing after it is worth asking about');
    });

    test('dismissing the fine-location rationale stops the sequence', () async {
      final gateway = FakeGateway();

      final result = await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: (_) async => false);

      expect(result.canDrive, isFalse);
      expect(gateway.requested, isEmpty);
    });

    test('refusing the optional steps still allows a drive', () async {
      final gateway = FakeGateway(requestResult: {
        PermissionStep.notifications: PermissionOutcome.denied,
        PermissionStep.backgroundLocation: PermissionOutcome.denied,
        PermissionStep.camera: PermissionOutcome.denied,
      });
      final rationale = acceptAll();

      final result = await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(result.canDrive, isTrue,
          reason: 'the app should degrade, not hold the drive hostage');
      expect(result.survivesScreenLock, isFalse);
      expect(result.declinedOptional, [
        PermissionStep.notifications,
        PermissionStep.backgroundLocation,
        PermissionStep.camera,
      ]);
    });

    test('asks for the remaining steps even after one is declined', () async {
      final gateway = FakeGateway(requestResult: {
        PermissionStep.notifications: PermissionOutcome.denied,
      });
      final rationale = acceptAll();

      await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(gateway.requested, contains(PermissionStep.backgroundLocation));
    });
  });

  group('surviving the screen lock', () {
    test('needs both background location and notifications', () async {
      final gateway = FakeGateway();
      final rationale = acceptAll();

      final result = await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(result.survivesScreenLock, isTrue);
    });

    test('background location alone is not enough', () async {
      final gateway = FakeGateway(requestResult: {
        PermissionStep.notifications: PermissionOutcome.denied,
      });
      final rationale = acceptAll();

      final result = await PermissionFlow(gateway: gateway)
          .requestForDrive(showRationale: rationale.fn);

      expect(result.granted(PermissionStep.backgroundLocation), isTrue);
      expect(result.survivesScreenLock, isFalse,
          reason: 'an invisible notification makes the service look broken');
    });
  });

  group('step metadata', () {
    test('only fine location is required', () {
      expect(PermissionStep.fineLocation.isRequired, isTrue);
      for (final step in PermissionFlow.driveSequence
          .where((s) => s != PermissionStep.fineLocation)) {
        expect(step.isRequired, isFalse, reason: '$step should be optional');
      }
    });

    test('every step explains itself and its consequence', () {
      for (final step in PermissionStep.values) {
        expect(step.title, isNotEmpty);
        expect(step.rationale, isNotEmpty);
        expect(step.consequenceIfDenied, isNotEmpty);
      }
    });
  });
}
