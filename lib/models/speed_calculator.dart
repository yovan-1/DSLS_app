import 'package:flutter/material.dart';

/// Weather conditions that affect driving safety and speed recommendations.
/// Each condition has an associated risk level.
enum WeatherCondition {
  /// Clear weather with no precipitation - optimal driving conditions
  clear,

  /// Overcast sky without precipitation - slightly reduced visibility
  cloudy,

  /// Light to moderate rain - reduced road traction
  rain,

  /// Heavy rainfall - significantly reduced visibility and traction
  heavyRain,

  /// Foggy conditions - severely reduced visibility
  fog,

  /// Snowy conditions - reduced traction and visibility
  snow,

  /// Freezing rain - extremely dangerous
  freezingRain,

  /// Sleet - mixed precipitation
  sleet,

  /// Hail - severe weather
  hail,

  /// Smoke - reduced visibility
  smoke,

  /// Dust - airborne particles
  dust,

  /// Haze - reduced visibility
  haze,

  /// Storm conditions - dangerous weather with high risk
  storm,
}

/// Time of day periods that affect driving conditions.
/// Different times have varying visibility and traffic patterns.
enum DayPeriod {
  /// Morning hours (6 AM - 12 PM) - moderate traffic, good visibility
  morning,

  /// Afternoon hours (12 PM - 6 PM) - peak traffic, best visibility
  afternoon,

  /// Evening hours (6 PM - 10 PM) - decreasing visibility, light traffic
  evening,

  /// Night hours (10 PM - 6 AM) - poor visibility, lowest traffic
  night,
}

/// Location types that determine base speed limits and safety requirements.
/// Each location has different speed regulations and risk factors.
enum LocationType {
  highway,
  suburban,
  urban,
  residential,
  schoolZone,
  constructionZone,
  roundabout,
  junction,
}

/// Visibility levels based on ambient light and weather conditions.
/// Detected automatically via camera brightness analysis.
enum VisibilityLevel {
  /// Excellent visibility (>180 brightness) - optimal conditions
  excellent,

  /// Good visibility (100-180 brightness) - slightly reduced
  good,

  /// Moderate visibility (50-100 brightness) - noticeably reduced
  moderate,

  /// Poor visibility (20-50 brightness) - significantly reduced
  poor,

  /// Very poor visibility (<20 brightness) - dangerous conditions
  veryPoor,
}

/// Parameters required for speed calculation.
/// These are collected from various sensors and user inputs.
class SpeedParameters {
  /// Current weather condition
  final WeatherCondition weather;

  /// Current time of day period
  final DayPeriod timeOfDay;

  /// Type of location (urban, highway, etc.)
  final LocationType location;

  /// Current visibility level
  final VisibilityLevel visibility;

  /// Base speed limit for the area (user configurable, default 60 km/h)
  final int baseSpeedLimit;

  const SpeedParameters({
    required this.weather,
    required this.timeOfDay,
    required this.location,
    required this.visibility,
    required this.baseSpeedLimit,
  });

  /// Factory constructor for default parameters
  factory SpeedParameters.defaults() {
    return const SpeedParameters(
      weather: WeatherCondition.clear,
      timeOfDay: DayPeriod.afternoon,
      location: LocationType.urban,
      visibility: VisibilityLevel.excellent,
      baseSpeedLimit: 60, // km/h
    );
  }
}

/// Result of speed calculation containing recommended speed and risk assessment.
class SpeedCalculationResult {
  /// The calculated recommended speed in km/h
  final int recommendedSpeed;

  /// Risk level as a percentage (0-100)
  final int riskLevel;

  /// Risk description: 'HIGH', 'MEDIUM', or 'LOW'
  final String riskDescription;

  /// List of warning messages based on current conditions
  final List<String> warnings;

  const SpeedCalculationResult({
    required this.recommendedSpeed,
    required this.riskLevel,
    required this.riskDescription,
    required this.warnings,
  });
}

/// Calculator class that determines recommended speed based on multiple factors.
///
/// The algorithm uses a multiplicative factor system where:
/// 1. Each parameter (weather, time, location, visibility) gets a percentage (0-100)
/// 2. All percentages are averaged and applied to the base speed limit
/// 3. The result is clamped between minimum (20) and maximum (130) km/h
///
/// Example:
/// - Base limit: 60 km/h
/// - Clear weather (100%) + Afternoon (100%) + Urban (70%) + Excellent visibility (100%)
/// - Average: (100+100+70+100)/4 = 92.5%
/// - Recommended: 60 * 0.925 = 55.5 -> 56 km/h
class SpeedCalculator {
  /// Minimum recommended speed in km/h
  static const int minSpeed = 20;

  /// Maximum recommended speed in km/h
  static const int maxSpeed = 130;

  /// Calculates the weather multiplier based on weather conditions.
  /// Returns a percentage (0-100) representing safety level.
  ///
  /// Multiplier breakdown:
  /// - Clear: 100% (optimal conditions)
  /// - Cloudy: 95% (slight reduction)
  /// - Rain: 75% (reduced traction)
  /// - Heavy Rain: 50% (significantly reduced)
  /// - Fog: 60% (visibility issue)
  /// - Snow: 45% (very slippery)
  /// - Storm: 40% (dangerous)
  static int _getWeatherMultiplier(WeatherCondition weather) {
    switch (weather) {
      case WeatherCondition.clear:
        return 100;
      case WeatherCondition.cloudy:
        return 95;
      case WeatherCondition.rain:
        return 75;
      case WeatherCondition.heavyRain:
        return 50;
      case WeatherCondition.fog:
        return 60;
      case WeatherCondition.snow:
        return 45;
      case WeatherCondition.freezingRain:
        return 35;
      case WeatherCondition.sleet:
        return 40;
      case WeatherCondition.hail:
        return 30;
      case WeatherCondition.smoke:
        return 55;
      case WeatherCondition.dust:
        return 50;
      case WeatherCondition.haze:
        return 65;
      case WeatherCondition.storm:
        return 40;
    }
  }

  /// Calculates the time of day multiplier based on driving conditions.
  /// Returns a percentage representing safety level for each time period.
  ///
  /// Multiplier breakdown:
  /// - Morning (6-12): 90% (moderate traffic)
  /// - Afternoon (12-18): 100% (best conditions)
  /// - Evening (18-22): 75% (reduced visibility)
  /// - Night (22-6): 60% (poor visibility)
  static int _getTimeMultiplier(DayPeriod time) {
    switch (time) {
      case DayPeriod.morning:
        return 90;
      case DayPeriod.afternoon:
        return 100;
      case DayPeriod.evening:
        return 75;
      case DayPeriod.night:
        return 60;
    }
  }

  /// Calculates the location multiplier based on location type.
  /// Returns a percentage representing speed safety for each location.
  ///
  /// Multiplier breakdown:
  /// - Highway: 100% (designed for high speed)
  /// - Suburban: 85% (moderate speed)
  /// - Urban: 70% (city traffic)
  /// - Residential: 50% (very low speed)
  /// - School Zone: 30% (speed bumps, children)
  /// - Construction Zone: 40% (reduced speed)
  static int _getLocationMultiplier(LocationType location) {
    switch (location) {
      case LocationType.highway:
        return 100;
      case LocationType.suburban:
        return 85;
      case LocationType.urban:
        return 70;
      case LocationType.residential:
        return 50;
      case LocationType.schoolZone:
        return 30;
      case LocationType.constructionZone:
        return 40;
      case LocationType.roundabout:
        return 20;
      case LocationType.junction:
        return 35;
    }
  }

  /// Calculates the visibility multiplier based on detected visibility level.
  /// Returns a percentage representing safety based on visibility.
  ///
  /// Multiplier breakdown:
  /// - Excellent: 100% (optimal)
  /// - Good: 90% (slightly reduced)
  /// - Moderate: 75% (noticeably reduced)
  /// - Poor: 55% (significantly reduced)
  /// - Very Poor: 35% (dangerous)
  static int _getVisibilityMultiplier(VisibilityLevel visibility) {
    switch (visibility) {
      case VisibilityLevel.excellent:
        return 100;
      case VisibilityLevel.good:
        return 90;
      case VisibilityLevel.moderate:
        return 75;
      case VisibilityLevel.poor:
        return 55;
      case VisibilityLevel.veryPoor:
        return 35;
    }
  }

  /// Main calculation method that computes recommended speed based on parameters.
  ///
  /// Algorithm:
  /// 1. Get multiplier for each parameter (weather, time, location, visibility)
  /// 2. Calculate overall multiplier as average of all four (divided by 400)
  /// 3. Apply multiplier to base speed limit
  /// 4. Clamp result between minSpeed and maxSpeed
  /// 5. Calculate risk level based on overall multiplier
  /// 6. Generate relevant warnings based on conditions
  ///
  /// Returns [SpeedCalculationResult] with recommended speed and risk assessment.
  static SpeedCalculationResult calculate(SpeedParameters params) {
    // Get individual multipliers for each parameter
    final weatherMult = _getWeatherMultiplier(params.weather);
    final timeMult = _getTimeMultiplier(params.timeOfDay);
    final locationMult = _getLocationMultiplier(params.location);
    final visibilityMult = _getVisibilityMultiplier(params.visibility);

    // Calculate overall multiplier as average of all four
    // Dividing by 400 (not 4) because each multiplier is already 0-100
    final overallMultiplier =
        (weatherMult + timeMult + locationMult + visibilityMult) / 400;

    // Apply multiplier to base speed limit and clamp to valid range
    int recommendedSpeed = (params.baseSpeedLimit * overallMultiplier).round();
    recommendedSpeed = recommendedSpeed.clamp(minSpeed, maxSpeed);

    // Calculate risk level (inverse of multiplier - higher multiplier = lower risk)
    // (overallMultiplier - 0.3) * 100 gives 0-70 range
    final riskScore = 100 - ((overallMultiplier - 0.3) * 100).round();
    final riskLevel = riskScore.clamp(0, 100);

    // Determine risk description based on risk level
    String riskDescription;
    if (riskLevel >= 70) {
      riskDescription = 'HIGH';
    } else if (riskLevel >= 40) {
      riskDescription = 'MEDIUM';
    } else {
      riskDescription = 'LOW';
    }

    // Generate warnings based on specific conditions
    List<String> warnings = [];

    // Weather-related warnings
    if (params.weather == WeatherCondition.heavyRain ||
        params.weather == WeatherCondition.storm ||
        params.weather == WeatherCondition.snow) {
      warnings.add('Severe weather conditions - drive with caution');
    }
    if (params.weather == WeatherCondition.fog) {
      warnings.add('Foggy conditions - use fog lights if available');
    }
    if (params.weather == WeatherCondition.rain && params.baseSpeedLimit > 50) {
      warnings.add('Wet roads - reduce speed to prevent hydroplaning');
    }

    // Time-related warnings
    if (params.timeOfDay == DayPeriod.night) {
      warnings.add(
        'Night driving - reduce speed and increase following distance',
      );
    }

    // Visibility-related warnings
    if (params.visibility == VisibilityLevel.poor ||
        params.visibility == VisibilityLevel.veryPoor) {
      warnings.add('Low visibility - drive carefully');
    }

    // Location-related warnings
    if (params.location == LocationType.schoolZone) {
      warnings.add('School zone - watch for children');
    }
    if (params.location == LocationType.constructionZone) {
      warnings.add('Construction zone - follow posted limits');
    }
    if (params.location == LocationType.residential) {
      warnings.add('Residential area - watch for pedestrians and cyclists');
    }

    return SpeedCalculationResult(
      recommendedSpeed: recommendedSpeed,
      riskLevel: riskLevel,
      riskDescription: riskDescription,
      warnings: warnings,
    );
  }

  /// Returns a human-readable label for a weather condition.
  static String getWeatherLabel(WeatherCondition weather) {
    switch (weather) {
      case WeatherCondition.clear:
        return 'Clear';
      case WeatherCondition.cloudy:
        return 'Cloudy';
      case WeatherCondition.rain:
        return 'Rain';
      case WeatherCondition.heavyRain:
        return 'Heavy Rain';
      case WeatherCondition.fog:
        return 'Fog';
      case WeatherCondition.snow:
        return 'Snow';
      case WeatherCondition.freezingRain:
        return 'Freezing Rain';
      case WeatherCondition.sleet:
        return 'Sleet';
      case WeatherCondition.hail:
        return 'Hail';
      case WeatherCondition.smoke:
        return 'Smoke';
      case WeatherCondition.dust:
        return 'Dust';
      case WeatherCondition.haze:
        return 'Haze';
      case WeatherCondition.storm:
        return 'Storm';
    }
  }

  /// Returns a human-readable label for a time period with hours.
  static String getTimeLabel(DayPeriod time) {
    switch (time) {
      case DayPeriod.morning:
        return 'Morning (6-12)';
      case DayPeriod.afternoon:
        return 'Afternoon (12-18)';
      case DayPeriod.evening:
        return 'Evening (18-22)';
      case DayPeriod.night:
        return 'Night (22-6)';
    }
  }

  /// Returns a human-readable label for a location type.
  static String getLocationLabel(LocationType location) {
    switch (location) {
      case LocationType.urban:
        return 'Urban';
      case LocationType.suburban:
        return 'Suburban';
      case LocationType.highway:
        return 'Highway';
      case LocationType.residential:
        return 'Residential';
      case LocationType.schoolZone:
        return 'School Zone';
      case LocationType.constructionZone:
        return 'Construction Zone';
      case LocationType.roundabout:
        return 'Roundabout';
      case LocationType.junction:
        return 'Junction';
    }
  }

  /// Returns a human-readable label for a visibility level.
  static String getVisibilityLabel(VisibilityLevel visibility) {
    switch (visibility) {
      case VisibilityLevel.excellent:
        return 'Excellent';
      case VisibilityLevel.good:
        return 'Good';
      case VisibilityLevel.moderate:
        return 'Moderate';
      case VisibilityLevel.poor:
        return 'Poor';
      case VisibilityLevel.veryPoor:
        return 'Very Poor';
    }
  }

  /// Returns an appropriate icon for a weather condition.
  static IconData getWeatherIcon(WeatherCondition weather) {
    switch (weather) {
      case WeatherCondition.clear:
        return Icons.wb_sunny;
      case WeatherCondition.cloudy:
        return Icons.cloud;
      case WeatherCondition.rain:
        return Icons.water_drop;
      case WeatherCondition.heavyRain:
        return Icons.thunderstorm;
      case WeatherCondition.fog:
        return Icons.foggy;
      case WeatherCondition.snow:
        return Icons.ac_unit;
      case WeatherCondition.freezingRain:
        return Icons.ac_unit;
      case WeatherCondition.sleet:
        return Icons.grain;
      case WeatherCondition.hail:
        return Icons.severe_cold;
      case WeatherCondition.smoke:
        return Icons.smoke_free;
      case WeatherCondition.dust:
        return Icons.cloud;
      case WeatherCondition.haze:
        return Icons.cloud_queue;
      case WeatherCondition.storm:
        return Icons.flash_on;
    }
  }

  /// Returns an appropriate icon for a location type.
  static IconData getLocationIcon(LocationType location) {
    switch (location) {
      case LocationType.urban:
        return Icons.location_city;
      case LocationType.suburban:
        return Icons.home;
      case LocationType.highway:
        return Icons.speed;
      case LocationType.residential:
        return Icons.house;
      case LocationType.schoolZone:
        return Icons.school;
      case LocationType.constructionZone:
        return Icons.construction;
      case LocationType.roundabout:
        return Icons.roundabout_right;
      case LocationType.junction:
        return Icons.change_history;
    }
  }
}
