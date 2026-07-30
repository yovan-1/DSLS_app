import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/services/alert_service.dart';
import 'package:dsls_app/services/settings_service.dart';

void main() {
  // SpeedAlertService's constructor builds a FlutterTts, which registers a
  // MethodChannel handler and needs a binding. Without this the whole group
  // throws before any assertion runs.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpeedAlertService', () {
    late SpeedAlertService service;

    setUp(() {
      service = SpeedAlertService();
    });

    group('default values', () {
      test('should have default alert threshold of 10', () {
        expect(service.alertThreshold, 10);
      });

      test('should have sound enabled by default', () {
        expect(service.enableSound, true);
      });

      test('should have vibration enabled by default', () {
        expect(service.enableVibration, true);
      });

      test('should have notifications enabled by default', () {
        expect(service.enableNotifications, true);
      });

      test('should have default warning ahead speed of 10', () {
        expect(service.warningAheadSpeed, 10);
      });

      test('should have default critical ahead speed of 20', () {
        expect(service.criticalAheadSpeed, 20);
      });

      test('should match AlertSettings defaults', () {
        // A mismatch here means a fresh install visibly jumps thresholds once
        // the async _loadSettings() lands.
        const defaults = AlertSettings();
        expect(service.alertThreshold, defaults.alertThreshold);
        expect(service.enableSound, defaults.enableSound);
        expect(service.enableVibration, defaults.enableVibration);
        expect(service.enableVoice, defaults.enableVoice);
        expect(service.enableNotifications, defaults.enableNotifications);
        expect(service.enableZoneAlerts, defaults.enableZoneAlerts);
        expect(service.warningAheadSpeed, defaults.warningAheadSpeed);
        expect(service.criticalAheadSpeed, defaults.criticalAheadSpeed);
      });
    });

    group('setAlertThreshold', () {
      test('should update alert threshold within bounds', () {
        service.setAlertThreshold(15);
        expect(service.alertThreshold, 15);
      });

      test('should clamp threshold to 0', () {
        service.setAlertThreshold(-5);
        expect(service.alertThreshold, 0);
      });

      test('should clamp threshold to 30', () {
        service.setAlertThreshold(50);
        expect(service.alertThreshold, 30);
      });
    });

    group('setEnableSound', () {
      test('should update sound setting', () {
        service.setEnableSound(false);
        expect(service.enableSound, false);
      });
    });

    group('setEnableVibration', () {
      test('should update vibration setting', () {
        service.setEnableVibration(false);
        expect(service.enableVibration, false);
      });
    });

    group('setEnableNotifications', () {
      test('should update notifications setting', () {
        service.setEnableNotifications(false);
        expect(service.enableNotifications, false);
      });
    });

    group('setWarningAheadSpeed', () {
      test('should update warning ahead speed', () {
        service.setWarningAheadSpeed(10);
        expect(service.warningAheadSpeed, 10);
      });

      test('should clamp to 0', () {
        service.setWarningAheadSpeed(-5);
        expect(service.warningAheadSpeed, 0);
      });

      test('should clamp to 20', () {
        service.setWarningAheadSpeed(25);
        expect(service.warningAheadSpeed, 20);
      });
    });

    group('setCriticalAheadSpeed', () {
      test('should update critical ahead speed', () {
        service.setCriticalAheadSpeed(20);
        expect(service.criticalAheadSpeed, 20);
      });

      test('should clamp to minimum 5', () {
        service.setCriticalAheadSpeed(2);
        expect(service.criticalAheadSpeed, 5);
      });

      test('should clamp to maximum 30', () {
        service.setCriticalAheadSpeed(35);
        expect(service.criticalAheadSpeed, 30);
      });
    });

    group('checkSpeed', () {
      test('should return safe when at recommended speed', () {
        final result = service.checkSpeed(50, 50);
        expect(result, AlertLevel.safe);
      });

      test('should return safe when below recommended speed', () {
        final result = service.checkSpeed(40, 50);
        expect(result, AlertLevel.safe);
      });

      test('should return caution when slightly over recommended speed', () {
        final result = service.checkSpeed(52, 50);
        expect(result, AlertLevel.caution);
      });

      test('should return warning when exceeding warning threshold', () {
        final result = service.checkSpeed(60, 50);
        expect(result, AlertLevel.warning);
      });

      test('should return critical when exceeding critical threshold', () {
        final result = service.checkSpeed(70, 50);
        expect(result, AlertLevel.critical);
      });
    });

    group('getAlertMessage', () {
      test('should return Speed OK when at recommended speed', () {
        final message = service.getAlertMessage(50, 50);
        expect(message, 'Speed OK');
      });

      test('should return caution message when slightly over', () {
        final message = service.getAlertMessage(52, 50);
        expect(message, 'Caution: Slightly above recommended speed');
      });

      test('should return warning message with speed diff', () {
        final message = service.getAlertMessage(60, 50);
        // Spelled out because these strings are fed to TTS.
        expect(
          message,
          'Warning: You are 10 kilometers per hour over the recommended speed',
        );
      });

      test('should return critical message with speed diff', () {
        final message = service.getAlertMessage(70, 50);
        expect(
          message,
          'CRITICAL: You are exceeding the recommended speed by '
              '20 kilometers per hour!',
        );
      });
    });
  });

  group('AlertLevel', () {
    test('should have all values', () {
      expect(AlertLevel.values, contains(AlertLevel.safe));
      expect(AlertLevel.values, contains(AlertLevel.caution));
      expect(AlertLevel.values, contains(AlertLevel.warning));
      expect(AlertLevel.values, contains(AlertLevel.critical));
    });

    test('safe should be first', () {
      expect(AlertLevel.safe.index, 0);
    });

    test('critical should be last', () {
      expect(AlertLevel.critical.index, 3);
    });
  });

  group('AlertSettings', () {
    const custom = AlertSettings(
      alertThreshold: 12,
      enableSound: false,
      enableVibration: false,
      enableVoice: false,
      enableNotifications: false,
      enableZoneAlerts: false,
      warningAheadSpeed: 7,
      criticalAheadSpeed: 22,
    );

    test('should create with explicit values', () {
      expect(custom.alertThreshold, 12);
      expect(custom.enableSound, false);
      expect(custom.enableVibration, false);
      expect(custom.enableVoice, false);
      expect(custom.enableNotifications, false);
      expect(custom.enableZoneAlerts, false);
      expect(custom.warningAheadSpeed, 7);
      expect(custom.criticalAheadSpeed, 22);
    });

    test('toJson should serialize every field', () {
      final json = custom.toJson();

      expect(json['alertThreshold'], 12);
      expect(json['enableSound'], false);
      expect(json['enableVibration'], false);
      expect(json['enableVoice'], false);
      expect(json['enableNotifications'], false);
      expect(json['enableZoneAlerts'], false);
      expect(json['warningAheadSpeed'], 7);
      expect(json['criticalAheadSpeed'], 22);
    });

    test('should survive a JSON round trip', () {
      final restored = AlertSettings.fromJson(custom.toJson());

      expect(restored.alertThreshold, custom.alertThreshold);
      expect(restored.enableSound, custom.enableSound);
      expect(restored.enableVibration, custom.enableVibration);
      expect(restored.enableVoice, custom.enableVoice);
      expect(restored.enableNotifications, custom.enableNotifications);
      expect(restored.enableZoneAlerts, custom.enableZoneAlerts);
      expect(restored.warningAheadSpeed, custom.warningAheadSpeed);
      expect(restored.criticalAheadSpeed, custom.criticalAheadSpeed);
    });

    test('fromJson should use defaults for missing values', () {
      final settings = AlertSettings.fromJson(<String, dynamic>{});

      expect(settings.alertThreshold, 10);
      expect(settings.enableSound, true);
      expect(settings.enableVibration, true);
      expect(settings.enableVoice, true);
      expect(settings.enableNotifications, true);
      expect(settings.enableZoneAlerts, true);
      expect(settings.warningAheadSpeed, 10);
      expect(settings.criticalAheadSpeed, 20);
    });

    test('copyWith should change only the named field', () {
      final updated = custom.copyWith(enableVoice: true);

      expect(updated.enableVoice, true);
      expect(updated.enableSound, custom.enableSound);
      expect(updated.alertThreshold, custom.alertThreshold);
      expect(updated.criticalAheadSpeed, custom.criticalAheadSpeed);
    });
  });
}