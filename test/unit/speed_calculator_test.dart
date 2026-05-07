import 'package:flutter/material.dart' hide DayPeriod;
import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/models/speed_calculator.dart';

void main() {
  group('SpeedCalculator', () {
    group('calculate', () {
      test('should return default values when created with defaults()', () {
        final params = SpeedParameters.defaults();
        expect(params.weather, WeatherCondition.clear);
        expect(params.timeOfDay, DayPeriod.afternoon);
        expect(params.location, LocationType.urban);
        expect(params.visibility, VisibilityLevel.excellent);
        expect(params.baseSpeedLimit, 60);
      });

      test('should calculate speed with clear weather', () {
        final params = SpeedParameters(
          weather: WeatherCondition.clear,
          timeOfDay: DayPeriod.afternoon,
          location: LocationType.urban,
          visibility: VisibilityLevel.excellent,
          baseSpeedLimit: 60,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.recommendedSpeed, greaterThan(0));
        expect(result.riskLevel, lessThanOrEqualTo(100));
        expect(result.riskDescription, isNotEmpty);
      });

      test('should calculate speed with storm weather - lowest multiplier', () {
        final params = SpeedParameters(
          weather: WeatherCondition.storm,
          timeOfDay: DayPeriod.night,
          location: LocationType.schoolZone,
          visibility: VisibilityLevel.veryPoor,
          baseSpeedLimit: 60,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.recommendedSpeed, lessThan(30));
        expect(result.riskLevel, greaterThanOrEqualTo(70));
        expect(result.riskDescription, 'HIGH');
      });

      test('should clamp recommended speed to minimum', () {
        final params = SpeedParameters(
          weather: WeatherCondition.storm,
          timeOfDay: DayPeriod.night,
          location: LocationType.schoolZone,
          visibility: VisibilityLevel.veryPoor,
          baseSpeedLimit: 30,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.recommendedSpeed, greaterThanOrEqualTo(SpeedCalculator.minSpeed));
      });

      test('should clamp recommended speed to maximum', () {
        final params = SpeedParameters(
          weather: WeatherCondition.clear,
          timeOfDay: DayPeriod.afternoon,
          location: LocationType.highway,
          visibility: VisibilityLevel.excellent,
          baseSpeedLimit: 200,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.recommendedSpeed, lessThanOrEqualTo(SpeedCalculator.maxSpeed));
      });
    });

    group('weather multipliers', () {
      test('clear should have 100% multiplier', () {
        final params = _createParamsWithWeather(WeatherCondition.clear);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, isNot(contains('Severe weather conditions')));
      });

      test('heavyRain should add warning', () {
        final params = _createParamsWithWeather(WeatherCondition.heavyRain);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Severe weather conditions - drive with caution'));
      });

      test('storm should add warning', () {
        final params = _createParamsWithWeather(WeatherCondition.storm);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Severe weather conditions - drive with caution'));
      });

      test('snow should add warning', () {
        final params = _createParamsWithWeather(WeatherCondition.snow);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Severe weather conditions - drive with caution'));
      });

      test('fog should add fog warning', () {
        final params = _createParamsWithWeather(WeatherCondition.fog);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Foggy conditions - use fog lights if available'));
      });

      test('rain should add wet road warning when speed > 50', () {
        final params = SpeedParameters(
          weather: WeatherCondition.rain,
          timeOfDay: DayPeriod.afternoon,
          location: LocationType.highway,
          visibility: VisibilityLevel.excellent,
          baseSpeedLimit: 60,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Wet roads - reduce speed to prevent hydroplaning'));
      });
    });

    group('time multipliers', () {
      test('night should add night driving warning', () {
        final params = _createParamsWithTime(DayPeriod.night);
        final result = SpeedCalculator.calculate(params);

        expect(
          result.warnings,
          contains('Night driving - reduce speed and increase following distance'),
        );
      });

      test('morning should have 90% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithTime(DayPeriod.morning));
        expect(result.recommendedSpeed, lessThan(60));
      });

      test('afternoon should have 100% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithTime(DayPeriod.afternoon));
        expect(result.recommendedSpeed, equals(60));
      });

      test('evening should have 75% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithTime(DayPeriod.evening));
        expect(result.recommendedSpeed, lessThan(60));
      });

      test('night should have 60% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithTime(DayPeriod.night));
        expect(result.recommendedSpeed, lessThan(55));
      });
    });

    group('location multipliers', () {
      test('schoolZone should add school warning', () {
        final params = _createParamsWithLocation(LocationType.schoolZone);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('School zone - watch for children'));
      });

      test('constructionZone should add warning', () {
        final params = _createParamsWithLocation(LocationType.constructionZone);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Construction zone - follow posted limits'));
      });

      test('residential should add warning', () {
        final params = _createParamsWithLocation(LocationType.residential);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Residential area - watch for pedestrians and cyclists'));
      });

      test('highway should have 100% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithLocation(LocationType.highway));
        expect(result.recommendedSpeed, equals(60));
      });

      test('suburban should have 85% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithLocation(LocationType.suburban));
        expect(result.recommendedSpeed, lessThan(60));
      });

      test('urban should have 70% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithLocation(LocationType.urban));
        expect(result.recommendedSpeed, lessThan(60));
      });

      test('schoolZone should have 30% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithLocation(LocationType.schoolZone));
        expect(result.recommendedSpeed, lessThan(55));
      });
    });

    group('visibility multipliers', () {
      test('poor visibility should add warning', () {
        final params = _createParamsWithVisibility(VisibilityLevel.poor);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Low visibility - drive carefully'));
      });

      test('veryPoor visibility should add warning', () {
        final params = _createParamsWithVisibility(VisibilityLevel.veryPoor);
        final result = SpeedCalculator.calculate(params);

        expect(result.warnings, contains('Low visibility - drive carefully'));
      });

      test('excellent visibility should have 100% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithVisibility(VisibilityLevel.excellent));
        expect(result.recommendedSpeed, equals(60));
      });

      test('good visibility should have 90% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithVisibility(VisibilityLevel.good));
        expect(result.recommendedSpeed, lessThan(60));
      });

      test('moderate visibility should have 75% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithVisibility(VisibilityLevel.moderate));
        expect(result.recommendedSpeed, lessThan(60));
      });

      test('poor visibility should have 55% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithVisibility(VisibilityLevel.poor));
        expect(result.recommendedSpeed, lessThan(55));
      });

      test('veryPoor visibility should have 35% multiplier', () {
        final result = SpeedCalculator.calculate(_createParamsWithVisibility(VisibilityLevel.veryPoor));
        expect(result.recommendedSpeed, lessThan(55));
      });
    });

    group('risk level calculation', () {
      test('HIGH risk when conditions are dangerous', () {
        final params = SpeedParameters(
          weather: WeatherCondition.storm,
          timeOfDay: DayPeriod.night,
          location: LocationType.schoolZone,
          visibility: VisibilityLevel.veryPoor,
          baseSpeedLimit: 60,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.riskDescription, 'HIGH');
        expect(result.riskLevel, greaterThanOrEqualTo(70));
      });

      test('MEDIUM risk for moderate conditions', () {
        final params = SpeedParameters(
          weather: WeatherCondition.rain,
          timeOfDay: DayPeriod.evening,
          location: LocationType.urban,
          visibility: VisibilityLevel.moderate,
          baseSpeedLimit: 60,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.riskDescription, 'MEDIUM');
        expect(result.riskLevel, greaterThanOrEqualTo(40));
        expect(result.riskLevel, lessThan(70));
      });

      test('LOW risk for optimal conditions', () {
        final params = SpeedParameters(
          weather: WeatherCondition.clear,
          timeOfDay: DayPeriod.afternoon,
          location: LocationType.highway,
          visibility: VisibilityLevel.excellent,
          baseSpeedLimit: 60,
        );
        final result = SpeedCalculator.calculate(params);

        expect(result.riskDescription, 'LOW');
        expect(result.riskLevel, lessThan(40));
      });
    });

    group('getWeatherLabel', () {
      test('should return correct labels for all weather conditions', () {
        expect(SpeedCalculator.getWeatherLabel(WeatherCondition.clear), 'Clear');
        expect(SpeedCalculator.getWeatherLabel(WeatherCondition.cloudy), 'Cloudy');
        expect(SpeedCalculator.getWeatherLabel(WeatherCondition.rain), 'Rain');
        expect(SpeedCalculator.getWeatherLabel(WeatherCondition.heavyRain), 'Heavy Rain');
        expect(SpeedCalculator.getWeatherLabel(WeatherCondition.fog), 'Fog');
        expect(SpeedCalculator.getWeatherLabel(WeatherCondition.snow), 'Snow');
        expect(SpeedCalculator.getWeatherLabel(WeatherCondition.storm), 'Storm');
      });
    });

    group('getTimeLabel', () {
      test('should return correct labels for all time periods', () {
        expect(SpeedCalculator.getTimeLabel(DayPeriod.morning), 'Morning (6-12)');
        expect(SpeedCalculator.getTimeLabel(DayPeriod.afternoon), 'Afternoon (12-18)');
        expect(SpeedCalculator.getTimeLabel(DayPeriod.evening), 'Evening (18-22)');
        expect(SpeedCalculator.getTimeLabel(DayPeriod.night), 'Night (22-6)');
      });
    });

    group('getLocationLabel', () {
      test('should return correct labels for all location types', () {
        expect(SpeedCalculator.getLocationLabel(LocationType.urban), 'Urban');
        expect(SpeedCalculator.getLocationLabel(LocationType.suburban), 'Suburban');
        expect(SpeedCalculator.getLocationLabel(LocationType.highway), 'Highway');
        expect(SpeedCalculator.getLocationLabel(LocationType.residential), 'Residential');
        expect(SpeedCalculator.getLocationLabel(LocationType.schoolZone), 'School Zone');
        expect(SpeedCalculator.getLocationLabel(LocationType.constructionZone), 'Construction Zone');
      });
    });

    group('getVisibilityLabel', () {
      test('should return correct labels for all visibility levels', () {
        expect(SpeedCalculator.getVisibilityLabel(VisibilityLevel.excellent), 'Excellent');
        expect(SpeedCalculator.getVisibilityLabel(VisibilityLevel.good), 'Good');
        expect(SpeedCalculator.getVisibilityLabel(VisibilityLevel.moderate), 'Moderate');
        expect(SpeedCalculator.getVisibilityLabel(VisibilityLevel.poor), 'Poor');
        expect(SpeedCalculator.getVisibilityLabel(VisibilityLevel.veryPoor), 'Very Poor');
      });
    });

    group('getWeatherIcon', () {
      test('should return correct icons for all weather conditions', () {
        expect(SpeedCalculator.getWeatherIcon(WeatherCondition.clear), Icons.wb_sunny);
        expect(SpeedCalculator.getWeatherIcon(WeatherCondition.cloudy), Icons.cloud);
        expect(SpeedCalculator.getWeatherIcon(WeatherCondition.rain), Icons.water_drop);
        expect(SpeedCalculator.getWeatherIcon(WeatherCondition.heavyRain), Icons.thunderstorm);
        expect(SpeedCalculator.getWeatherIcon(WeatherCondition.fog), Icons.foggy);
        expect(SpeedCalculator.getWeatherIcon(WeatherCondition.snow), Icons.ac_unit);
        expect(SpeedCalculator.getWeatherIcon(WeatherCondition.storm), Icons.flash_on);
      });
    });

    group('getLocationIcon', () {
      test('should return correct icons for all location types', () {
        expect(SpeedCalculator.getLocationIcon(LocationType.urban), Icons.location_city);
        expect(SpeedCalculator.getLocationIcon(LocationType.suburban), Icons.home);
        expect(SpeedCalculator.getLocationIcon(LocationType.highway), Icons.speed);
        expect(SpeedCalculator.getLocationIcon(LocationType.residential), Icons.house);
        expect(SpeedCalculator.getLocationIcon(LocationType.schoolZone), Icons.school);
        expect(SpeedCalculator.getLocationIcon(LocationType.constructionZone), Icons.construction);
      });
    });

    group('SpeedParameters', () {
      test('should create with required parameters', () {
        final params = SpeedParameters(
          weather: WeatherCondition.rain,
          timeOfDay: DayPeriod.evening,
          location: LocationType.suburban,
          visibility: VisibilityLevel.good,
          baseSpeedLimit: 80,
        );

        expect(params.weather, WeatherCondition.rain);
        expect(params.timeOfDay, DayPeriod.evening);
        expect(params.location, LocationType.suburban);
        expect(params.visibility, VisibilityLevel.good);
        expect(params.baseSpeedLimit, 80);
      });

      test('defaults should have correct values', () {
        final params = SpeedParameters.defaults();

        expect(params.weather, WeatherCondition.clear);
        expect(params.timeOfDay, DayPeriod.afternoon);
        expect(params.location, LocationType.urban);
        expect(params.visibility, VisibilityLevel.excellent);
        expect(params.baseSpeedLimit, 60);
      });
    });

    group('SpeedCalculationResult', () {
      test('should store all values correctly', () {
        const result = SpeedCalculationResult(
          recommendedSpeed: 55,
          riskLevel: 25,
          riskDescription: 'LOW',
          warnings: ['Test warning'],
        );

        expect(result.recommendedSpeed, 55);
        expect(result.riskLevel, 25);
        expect(result.riskDescription, 'LOW');
        expect(result.warnings, ['Test warning']);
      });
    });
  });
}

SpeedParameters _createParamsWithWeather(WeatherCondition weather) {
  return SpeedParameters(
    weather: weather,
    timeOfDay: DayPeriod.afternoon,
    location: LocationType.highway,
    visibility: VisibilityLevel.excellent,
    baseSpeedLimit: 60,
  );
}

SpeedParameters _createParamsWithTime(DayPeriod time) {
  return SpeedParameters(
    weather: WeatherCondition.clear,
    timeOfDay: time,
    location: LocationType.highway,
    visibility: VisibilityLevel.excellent,
    baseSpeedLimit: 60,
  );
}

SpeedParameters _createParamsWithLocation(LocationType location) {
  return SpeedParameters(
    weather: WeatherCondition.clear,
    timeOfDay: DayPeriod.afternoon,
    location: location,
    visibility: VisibilityLevel.excellent,
    baseSpeedLimit: 60,
  );
}

SpeedParameters _createParamsWithVisibility(VisibilityLevel visibility) {
  return SpeedParameters(
    weather: WeatherCondition.clear,
    timeOfDay: DayPeriod.afternoon,
    location: LocationType.highway,
    visibility: visibility,
    baseSpeedLimit: 60,
  );
}