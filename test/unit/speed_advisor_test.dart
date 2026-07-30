import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/models/speed_calculator.dart'
    show LocationType, VisibilityLevel, WeatherCondition;
import 'package:dsls_app/models/speed_model/advisory.dart';
import 'package:dsls_app/models/speed_model/road_conditions.dart';
import 'package:dsls_app/models/speed_model/solar_position.dart';
import 'package:dsls_app/models/speed_model/speed_advisor.dart';
import 'package:dsls_app/models/speed_model/speed_recommendation.dart';

/// Severity order used by the monotonicity properties: worsening any single
/// input must never raise the recommended speed.
const _weatherWorstToBest = <WeatherCondition>[
  WeatherCondition.clear,
  WeatherCondition.cloudy,
  WeatherCondition.haze,
  WeatherCondition.rain,
  WeatherCondition.heavyRain,
  WeatherCondition.snow,
  WeatherCondition.freezingRain,
];

const _daylightBestToWorst = <DaylightState>[
  DaylightState.daylight,
  DaylightState.twilight,
  DaylightState.night,
];

const _visibilityBestToWorst = <VisibilityLevel>[
  VisibilityLevel.excellent,
  VisibilityLevel.good,
  VisibilityLevel.moderate,
  VisibilityLevel.poor,
  VisibilityLevel.veryPoor,
];

RoadConditions _conditions({
  int limit = 60,
  LimitSource source = LimitSource.posted,
  LocationType roadClass = LocationType.urban,
  WeatherCondition weather = WeatherCondition.clear,
  DaylightState daylight = DaylightState.daylight,
  VisibilityLevel? camera,
  bool? isLit,
}) {
  return RoadConditions(
    speedLimitKph: limit,
    limitSource: source,
    roadClass: roadClass,
    weather: weather,
    daylight: daylight,
    cameraVisibility: camera,
    isLit: isLit,
  );
}

void main() {
  group('ceiling property', () {
    test('never recommends above the posted limit, across all conditions', () {
      for (final limit in [20, 30, 50, 60, 80, 100, 120]) {
        for (final weather in WeatherCondition.values) {
          for (final daylight in DaylightState.values) {
            for (final camera in [null, ...VisibilityLevel.values]) {
              final result = SpeedAdvisor.evaluate(
                _conditions(
                  limit: limit,
                  weather: weather,
                  daylight: daylight,
                  camera: camera,
                ),
              );

              expect(
                result.recommendedSpeedKph,
                lessThanOrEqualTo(limit),
                reason: 'limit=$limit weather=${weather.name} '
                    'daylight=${daylight.name} camera=${camera?.name}',
              );
            }
          }
        }
      }
    });
  });

  group('monotonicity properties', () {
    // These are the tests that would have caught the old model's averaging
    // defect: it let one severe hazard be diluted by three benign factors.

    test('worsening weather never raises the recommendation', () {
      for (final daylight in DaylightState.values) {
        var previous = 1 << 30;
        for (final weather in _weatherWorstToBest) {
          final result = SpeedAdvisor.evaluate(
            _conditions(limit: 100, weather: weather, daylight: daylight),
          );
          expect(
            result.recommendedSpeedKph,
            lessThanOrEqualTo(previous),
            reason: 'weather=${weather.name} daylight=${daylight.name}',
          );
          previous = result.recommendedSpeedKph;
        }
      }
    });

    test('losing daylight never raises the recommendation', () {
      for (final weather in _weatherWorstToBest) {
        var previous = 1 << 30;
        for (final daylight in _daylightBestToWorst) {
          final result = SpeedAdvisor.evaluate(
            _conditions(limit: 100, weather: weather, daylight: daylight),
          );
          expect(result.recommendedSpeedKph, lessThanOrEqualTo(previous));
          previous = result.recommendedSpeedKph;
        }
      }
    });

    test('worsening measured light never raises the recommendation', () {
      var previous = 1 << 30;
      for (final camera in _visibilityBestToWorst) {
        final result = SpeedAdvisor.evaluate(
          _conditions(limit: 100, camera: camera),
        );
        expect(result.recommendedSpeedKph, lessThanOrEqualTo(previous));
        previous = result.recommendedSpeedKph;
      }
    });
  });

  group('severe hazards are not averaged away', () {
    test('freezing rain on a clear-daylight highway still cuts speed hard', () {
      // The old model scored this case at 82.5% of the limit, because three
      // benign factors outvoted one severe one.
      final result = SpeedAdvisor.evaluate(
        _conditions(
          limit: 100,
          roadClass: LocationType.highway,
          weather: WeatherCondition.freezingRain,
          daylight: DaylightState.daylight,
          camera: VisibilityLevel.excellent,
        ),
      );

      expect(result.recommendedSpeedKph, lessThan(60));
      expect(result.bindingConstraint, BindingConstraint.grip);
      expect(
        result.advisories.map((a) => a.code),
        contains(AdvisoryCode.iceRisk),
      );
    });

    test('dense fog binds on sight distance regardless of good grip', () {
      final result = SpeedAdvisor.evaluate(
        _conditions(limit: 100, weather: WeatherCondition.fog),
      );

      expect(result.bindingConstraint, BindingConstraint.sightDistance);
      expect(result.recommendedSpeedKph, lessThan(50));
      expect(
        result.advisories.map((a) => a.code),
        contains(AdvisoryCode.fog),
      );
    });
  });

  group('location is not double-counted', () {
    test('a posted 30 km/h school zone is not reduced again', () {
      // The old model replaced the base limit with the zone's 30 km/h and then
      // multiplied by another 0.30, giving 9 km/h before a floor rescued it.
      final result = SpeedAdvisor.evaluate(
        _conditions(
          limit: 30,
          source: LimitSource.curated,
          roadClass: LocationType.schoolZone,
        ),
      );

      expect(result.recommendedSpeedKph, 30);
      expect(result.bindingConstraint, BindingConstraint.postedLimit);
      expect(result.conditionRisk, 0);
      // The advisory still fires — the driver is told about the school zone,
      // the number just is not reduced twice.
      expect(
        result.advisories.map((a) => a.code),
        contains(AdvisoryCode.schoolZone),
      );
    });

    test('an inferred limit does get an uncertainty margin', () {
      final result = SpeedAdvisor.evaluate(
        _conditions(
          limit: 60,
          source: LimitSource.inferred,
          roadClass: LocationType.residential,
        ),
      );

      expect(result.recommendedSpeedKph, lessThan(60));
      expect(
        result.bindingConstraint,
        BindingConstraint.inferredLimitMargin,
      );
      expect(
        result.advisories.map((a) => a.code),
        contains(AdvisoryCode.inferredLimit),
      );
    });
  });

  group('risk scale', () {
    test('is exactly 0 in perfect conditions', () {
      // The old scale bottomed out at 30 and called a quiet residential street
      // at noon "MEDIUM".
      final result = SpeedAdvisor.evaluate(
        _conditions(
          limit: 50,
          source: LimitSource.posted,
          roadClass: LocationType.residential,
          weather: WeatherCondition.clear,
          daylight: DaylightState.daylight,
          camera: VisibilityLevel.excellent,
        ),
      );

      expect(result.conditionRisk, 0);
      expect(result.riskBand, RiskBand.low);
    });

    test('reaches the high band on ice at night on an unlit road', () {
      final result = SpeedAdvisor.evaluate(
        _conditions(
          limit: 100,
          weather: WeatherCondition.freezingRain,
          daylight: DaylightState.night,
          camera: VisibilityLevel.veryPoor,
          isLit: false,
        ),
      );

      expect(result.conditionRisk, greaterThanOrEqualTo(65));
      expect(result.riskBand, RiskBand.high);
    });

    test('is relative to the ceiling, so the same hazard reads worse on a '
        'faster road', () {
      // conditionRisk measures how far conditions have pushed the safe speed
      // below this road's own limit. Identical ice and darkness therefore score
      // higher on a 120 road than on a 100 one, which is the intended reading:
      // the gap between what the road allows and what is safe is larger.
      RoadConditions iceAtNight(int limit) => _conditions(
            limit: limit,
            weather: WeatherCondition.freezingRain,
            daylight: DaylightState.night,
            camera: VisibilityLevel.veryPoor,
            isLit: false,
          );

      final on100 = SpeedAdvisor.evaluate(iceAtNight(100));
      final on120 = SpeedAdvisor.evaluate(iceAtNight(120));

      expect(on120.conditionRisk, greaterThan(on100.conditionRisk));
      expect(on120.riskBand, RiskBand.severe);
      // The absolute advice is the same — only the risk framing differs.
      expect(
        on120.recommendedSpeedKph,
        on100.recommendedSpeedKph,
      );
    });
  });

  group('stop recommendation', () {
    test('advises stopping rather than crawling when conditions collapse', () {
      final result = SpeedAdvisor.evaluate(
        _conditions(
          limit: 30,
          weather: WeatherCondition.freezingRain,
          daylight: DaylightState.night,
          camera: VisibilityLevel.veryPoor,
          isLit: false,
        ),
      );

      expect(result.stopRecommended, isTrue);
      expect(
        result.advisories.map((a) => a.code),
        contains(AdvisoryCode.stopRecommended),
      );
    });

    test('does not fire in ordinary conditions', () {
      final result = SpeedAdvisor.evaluate(_conditions(limit: 50));
      expect(result.stopRecommended, isFalse);
    });
  });

  group('lit roads', () {
    test('a lit road at night is treated far less harshly than an unlit one',
        () {
      final lit = SpeedAdvisor.evaluate(
        _conditions(limit: 100, daylight: DaylightState.night, isLit: true),
      );
      final unlit = SpeedAdvisor.evaluate(
        _conditions(limit: 100, daylight: DaylightState.night, isLit: false),
      );

      expect(lit.recommendedSpeedKph, greaterThan(unlit.recommendedSpeedKph));
    });

    test('unknown lighting sits between the two', () {
      final unknown = SpeedAdvisor.evaluate(
        _conditions(limit: 100, daylight: DaylightState.night),
      );
      final lit = SpeedAdvisor.evaluate(
        _conditions(limit: 100, daylight: DaylightState.night, isLit: true),
      );
      final unlit = SpeedAdvisor.evaluate(
        _conditions(limit: 100, daylight: DaylightState.night, isLit: false),
      );

      expect(unknown.recommendedSpeedKph, lessThan(lit.recommendedSpeedKph));
      expect(
        unknown.recommendedSpeedKph,
        greaterThan(unlit.recommendedSpeedKph),
      );
    });
  });

  group('binding constraint is reported', () {
    test('names the headlight limit at night on an unlit road', () {
      final result = SpeedAdvisor.evaluate(
        _conditions(limit: 100, daylight: DaylightState.night, isLit: false),
      );

      expect(result.bindingConstraint, BindingConstraint.sightDistance);
      expect(result.bindingReason, 'Limited by headlight range');
    });

    test('names the posted limit when conditions impose nothing', () {
      final result = SpeedAdvisor.evaluate(_conditions(limit: 50));
      expect(result.bindingConstraint, BindingConstraint.postedLimit);
      expect(result.bindingReason, 'Posted limit');
    });
  });
}
