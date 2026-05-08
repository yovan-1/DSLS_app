import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/services/alert_service.dart';

void main() {
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

      test('should have default warning ahead speed of 5', () {
        expect(service.warningAheadSpeed, 5);
      });

      test('should have default critical ahead speed of 15', () {
        expect(service.criticalAheadSpeed, 15);
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
        expect(message, 'Warning: You are 10 km/h over the recommended speed');
      });

      test('should return critical message with speed diff', () {
        final message = service.getAlertMessage(70, 50);
        expect(message, 'CRITICAL: You are exceeding the recommended speed by 20 km/h!');
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
    test('should create with required parameters', () {
      const settings = AlertSettings(
        threshold: 10,
        sound: true,
        vibration: true,
        notifications: true,
        warningAhead: 5,
        criticalAhead: 15,
      );

      expect(settings.threshold, 10);
      expect(settings.sound, true);
      expect(settings.vibration, true);
      expect(settings.notifications, true);
      expect(settings.warningAhead, 5);
      expect(settings.criticalAhead, 15);
    });

    test('toJson should serialize', () {
      const settings = AlertSettings(
        threshold: 10,
        sound: true,
        vibration: true,
        notifications: true,
        warningAhead: 5,
        criticalAhead: 15,
      );

      final json = settings.toJson();

      expect(json['threshold'], 10);
      expect(json['sound'], true);
      expect(json['warningAhead'], 5);
      expect(json['criticalAhead'], 15);
    });

    test('fromJson should deserialize', () {
      final json = {
        'threshold': 10,
        'sound': true,
        'vibration': true,
        'notifications': true,
        'warningAhead': 5,
        'criticalAhead': 15,
      };

      final settings = AlertSettings.fromJson(json);

      expect(settings.threshold, 10);
      expect(settings.sound, true);
      expect(settings.warningAhead, 5);
    });

    test('fromJson should use defaults for missing values', () {
      final json = <String, dynamic>{};

      final settings = AlertSettings.fromJson(json);

      expect(settings.threshold, 10);
      expect(settings.sound, true);
      expect(settings.vibration, true);
      expect(settings.notifications, true);
      expect(settings.warningAhead, 5);
      expect(settings.criticalAhead, 15);
    });
  });
}
