import 'package:dsls_app/models/speed_calculator.dart'
    show VisibilityLevel, WeatherCondition;
import 'package:dsls_app/services/visibility_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VisibilityService service;

  setUp(() {
    service = VisibilityService();
  });

  /// Feeds a brightness reading as a camera sample would. The capture pipeline
  /// is platform code; the decision made from a brightness figure is not, and
  /// that is the part with the bugs in it.
  void sample(double brightness) => service.ingestBrightness(brightness);

  group('weather and camera are assessed separately', () {
    test('a camera sample does not erase the weather assessment', () {
      service.updateVisibilityFromWeather(WeatherCondition.fog);
      expect(service.weatherVisibility, VisibilityLevel.moderate);

      // A bright sample used to overwrite the single shared field, discarding
      // the fog penalty until the next weather fetch half an hour later.
      sample(250);

      expect(service.cameraVisibility, VisibilityLevel.excellent);
      expect(service.weatherVisibility, VisibilityLevel.moderate,
          reason: 'fog does not clear because the lens is bright');
    });

    test('effective visibility is the worse of the two', () {
      service.updateVisibilityFromWeather(WeatherCondition.fog);
      sample(250);

      expect(service.effectiveVisibility, VisibilityLevel.moderate);
    });

    test('a dark road beats clear weather', () {
      service.updateVisibilityFromWeather(WeatherCondition.clear);
      sample(30);

      expect(service.effectiveVisibility, VisibilityLevel.poor);
    });

    test('falls back to whichever is known', () {
      expect(service.effectiveVisibility, isNull);

      service.updateVisibilityFromWeather(WeatherCondition.rain);
      expect(service.effectiveVisibility, VisibilityLevel.good);
    });

    test('clear and cloudy impose no weather ceiling', () {
      service.updateVisibilityFromWeather(WeatherCondition.clear);
      expect(service.weatherVisibility, VisibilityLevel.excellent);

      service.updateVisibilityFromWeather(WeatherCondition.cloudy);
      expect(service.weatherVisibility, VisibilityLevel.excellent);
    });
  });

  group('brightness mapping', () {
    test('maps the full range', () {
      sample(250);
      expect(service.cameraVisibility, VisibilityLevel.excellent);

      sample(150);
      expect(service.cameraVisibility, VisibilityLevel.good);

      sample(75);
      expect(service.cameraVisibility, VisibilityLevel.moderate);

      sample(30);
      expect(service.cameraVisibility, VisibilityLevel.poor);

      sample(15);
      expect(service.cameraVisibility, VisibilityLevel.veryPoor);
    });
  });

  group('pocket detection', () {
    test('a dark lens while stationary is a dark road, not a pocket', () {
      service.updateVehicleSpeed(0);

      sample(1);
      sample(1);
      sample(1);

      expect(service.cameraVisibility, VisibilityLevel.veryPoor,
          reason: 'parked in the dark is a legitimate very-poor reading');
    });

    test('a dark lens at speed is reported as unknown', () {
      service.updateVehicleSpeed(90);

      sample(1);
      sample(1);

      expect(service.cameraVisibility, isNull,
          reason: 'pitch black on a motorway is a bag, not a tunnel');
    });

    test('one dark frame is not enough', () {
      service.updateVehicleSpeed(90);

      sample(1);

      expect(service.cameraVisibility, VisibilityLevel.veryPoor,
          reason: 'a hand over the lens for one frame should not trip it');
    });

    test('a merely dim reading at speed is still a real measurement', () {
      service.updateVehicleSpeed(90);

      sample(15);
      sample(15);

      expect(service.cameraVisibility, VisibilityLevel.veryPoor,
          reason: 'night driving with headlights is dim, not black');
    });

    test('recovers once the lens sees light again', () {
      service.updateVehicleSpeed(90);
      sample(1);
      sample(1);
      expect(service.cameraVisibility, isNull);

      sample(200);

      expect(service.cameraVisibility, VisibilityLevel.excellent);
    });

    test('slow speed does not trip the detector', () {
      service.updateVehicleSpeed(5);

      sample(1);
      sample(1);

      expect(service.cameraVisibility, VisibilityLevel.veryPoor);
    });
  });

  group('suspension', () {
    test('suspending clears the camera reading', () async {
      sample(200);
      expect(service.cameraVisibility, VisibilityLevel.excellent);

      await service.suspend();

      expect(service.isSuspended, isTrue);
      expect(service.cameraVisibility, isNull,
          reason: 'a backgrounded app must not report a stale reading');
    });

    test('the weather assessment survives suspension', () async {
      service.updateVisibilityFromWeather(WeatherCondition.fog);

      await service.suspend();

      expect(service.weatherVisibility, VisibilityLevel.moderate);
      expect(service.effectiveVisibility, VisibilityLevel.moderate);
    });

    test('stop clears the camera reading too', () async {
      sample(200);

      await service.stop();

      expect(service.cameraVisibility, isNull);
    });
  });
}
