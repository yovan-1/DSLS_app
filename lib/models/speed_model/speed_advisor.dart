import 'dart:math' as math;

import '../speed_calculator.dart' show LocationType, WeatherCondition;
import 'advisory.dart';
import 'friction_model.dart';
import 'road_conditions.dart';
import 'sight_distance_model.dart';
import 'solar_position.dart';
import 'speed_recommendation.dart';
import 'stopping_distance.dart';

/// Computes a recommended speed by composing independent upper bounds and
/// taking the most restrictive.
///
/// ## Why `min`, not an average
///
/// The previous model averaged four invented percentages, which let one severe
/// hazard be diluted by three benign factors: hail on a clear afternoon on a
/// highway with good visibility scored `(30+100+100+100)/400 = 0.825`, so the
/// app recommended 82.5% of the limit *in hail*.
///
/// Each constraint here is an independent upper bound on a safe speed. Breaking
/// any one of them is unsafe no matter how comfortable the others are, so they
/// compose with `min`, not with a mean or a product.
///
/// ## The constraints
///
/// * `v_ceiling` — the posted or curated limit. Never exceeded.
/// * `v_sight`   — the fastest speed you can still stop from within the
///                 distance you can see ([StoppingDistance]).
/// * `v_grip`    — the ceiling scaled for reduced friction ([FrictionModel]).
/// * `v_context` — an uncertainty margin, applied *only* when the limit was
///                 guessed rather than posted.
class SpeedAdvisor {
  const SpeedAdvisor._();

  /// Below this the advice is to stop, not to crawl.
  static const int stopThresholdKph = 15;

  /// Uncertainty margins for an unverified limit, by road class.
  ///
  /// These apply only when [LimitSource.inferred] — that is, when the app is
  /// guessing. A posted limit already accounts for its surroundings.
  static const Map<LocationType, double> _inferredMargin = {
    LocationType.highway: 1.00,
    LocationType.suburban: 0.90,
    LocationType.urban: 0.80,
    LocationType.residential: 0.60,
    LocationType.constructionZone: 0.60,
    LocationType.junction: 0.60,
    LocationType.schoolZone: 0.50,
    LocationType.roundabout: 0.50,
  };

  static SpeedRecommendation evaluate(RoadConditions conditions) {
    final ceiling = conditions.speedLimitKph.toDouble();
    final surface = FrictionModel.surfaceFor(conditions.weather);
    final friction = FrictionModel.frictionFor(surface);

    final sight = SightDistanceModel.compute(
      daylight: conditions.daylight,
      weather: conditions.weather,
      cameraVisibility: conditions.cameraVisibility,
      isLit: conditions.isLit,
    );

    final vSight = StoppingDistance.maxSpeedForSightDistance(
      sight.metres,
      friction: friction,
      grade: conditions.grade,
    );

    final vGrip = ceiling * FrictionModel.gripFactor(surface);

    final vContext = conditions.limitSource == LimitSource.inferred
        ? ceiling * (_inferredMargin[conditions.roadClass] ?? 0.80)
        : double.infinity;

    // The most restrictive bound wins.
    var binding = BindingConstraint.postedLimit;
    var best = ceiling;

    if (vSight < best) {
      best = vSight;
      binding = BindingConstraint.sightDistance;
    }
    if (vGrip < best) {
      best = vGrip;
      binding = BindingConstraint.grip;
    }
    if (vContext < best) {
      best = vContext;
      binding = BindingConstraint.inferredLimitMargin;
    }

    final recommended = math.max(best.round(), 0);

    // Risk is how much the conditions eroded the ceiling. Perfect conditions
    // give exactly 0.
    final conditionRisk = ceiling <= 0
        ? 0
        : (100 * (1 - (recommended / ceiling))).round().clamp(0, 100);

    final stopRecommended = recommended < stopThresholdKph;

    return SpeedRecommendation(
      recommendedSpeedKph: recommended,
      speedLimitKph: conditions.speedLimitKph,
      bindingConstraint: binding,
      sightDistance: sight,
      surface: surface,
      conditionRisk: conditionRisk,
      stopRecommended: stopRecommended,
      advisories: _advisories(conditions, surface, sight, stopRecommended),
    );
  }

  static List<Advisory> _advisories(
    RoadConditions conditions,
    SurfaceState surface,
    SightDistance sight,
    bool stopRecommended,
  ) {
    final advisories = <Advisory>[];

    void add(AdvisoryCode code, AdvisorySeverity severity, String message) {
      advisories.add(
        Advisory(code: code, severity: severity, message: message),
      );
    }

    if (stopRecommended) {
      add(
        AdvisoryCode.stopRecommended,
        AdvisorySeverity.danger,
        'Conditions are unsafe for driving — consider pulling over.',
      );
    }

    switch (surface) {
      case SurfaceState.ice:
        add(
          AdvisoryCode.iceRisk,
          AdvisorySeverity.danger,
          'Ice risk — braking distances can be several times longer.',
        );
        break;
      case SurfaceState.snow:
        add(
          AdvisoryCode.severeWeather,
          AdvisorySeverity.danger,
          'Snow or sleet — reduce speed and increase following distance.',
        );
        break;
      case SurfaceState.standingWater:
        add(
          AdvisoryCode.severeWeather,
          AdvisorySeverity.danger,
          'Heavy rain — risk of standing water and aquaplaning.',
        );
        break;
      case SurfaceState.wet:
        add(
          AdvisoryCode.wetRoad,
          AdvisorySeverity.caution,
          'Wet road — allow extra braking distance.',
        );
        break;
      case SurfaceState.dry:
        break;
    }

    if (conditions.weather == WeatherCondition.fog) {
      add(
        AdvisoryCode.fog,
        AdvisorySeverity.danger,
        'Fog — use fog lights and keep well back.',
      );
    }

    switch (conditions.daylight) {
      case DaylightState.night:
        add(
          AdvisoryCode.nightDriving,
          AdvisorySeverity.caution,
          'Night driving — do not outrun your headlights.',
        );
        break;
      case DaylightState.lowSun:
        add(
          AdvisoryCode.lowSunGlare,
          AdvisorySeverity.caution,
          'Low sun — glare may hide pedestrians and cyclists.',
        );
        break;
      case DaylightState.twilight:
      case DaylightState.daylight:
        break;
    }

    if (sight.limiter == SightLimiter.measuredLight) {
      add(
        AdvisoryCode.lowVisibility,
        AdvisorySeverity.caution,
        'Low measured light — visibility is worse than forecast.',
      );
    }

    switch (conditions.roadClass) {
      case LocationType.schoolZone:
        add(
          AdvisoryCode.schoolZone,
          AdvisorySeverity.danger,
          'School zone — watch for children.',
        );
        break;
      case LocationType.constructionZone:
        add(
          AdvisoryCode.constructionZone,
          AdvisorySeverity.caution,
          'Construction zone — follow posted limits and signals.',
        );
        break;
      case LocationType.residential:
        add(
          AdvisoryCode.residentialArea,
          AdvisorySeverity.caution,
          'Residential area — watch for pedestrians and cyclists.',
        );
        break;
      case LocationType.roundabout:
        add(
          AdvisoryCode.roundaboutAhead,
          AdvisorySeverity.caution,
          'Roundabout — give way and slow down on approach.',
        );
        break;
      case LocationType.junction:
        add(
          AdvisoryCode.junctionAhead,
          AdvisorySeverity.caution,
          'Junction — watch for turning traffic.',
        );
        break;
      case LocationType.highway:
      case LocationType.suburban:
      case LocationType.urban:
        break;
    }

    if (conditions.limitSource == LimitSource.inferred) {
      add(
        AdvisoryCode.inferredLimit,
        AdvisorySeverity.info,
        'No mapped speed limit here — showing a conservative estimate. '
        'Follow the posted signs.',
      );
    }

    return advisories;
  }
}
