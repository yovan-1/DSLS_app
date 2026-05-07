# Recommended Speed Mapping - Technical Documentation

This document explains how the Dynamic Speed Limit System (DSLS) calculates recommended speeds through a series of parameter mappings.

---

## 1. Overview of the Mapping Pipeline

The recommended speed is calculated through a **multi-factor multiplicative system** that transforms 4 input parameters into a single recommended speed value:

```
INPUTS                          MAPPING LAYER                    OUTPUT
┌─────────────┐                ┌─────────────────────┐         ┌──────────────┐
│   Weather   │ ──────────────► │ _getWeatherMultiplier│────────►│              │
├─────────────┤                └─────────────────────┘         │              │
│   Time      │ ──────────────► │ _getTimeMultiplier   │────────►│   RECOMMENDED│
├─────────────┤                └─────────────────────┘         │    SPEED     │
│   Location  │ ──────────────► │ _getLocationMultiplier│───────►│              │
├─────────────┤                └─────────────────────┘         │              │
│  Visibility │ ──────────────► │ _getVisibilityMultiplier│────►│              │
└─────────────┘                └─────────────────────┘         └──────────────┘
                                      │
                                      ▼
                              ┌──────────────┐
                              │  calculate() │
                              │  main method │
                              └──────────────┘
```

---

## 2. Individual Parameter Mappings

### 2.1 Weather Condition Mapping

**Location:** `lib/models/speed_calculator.dart:167-193`

```dart
static int _getWeatherMultiplier(WeatherCondition weather) {
  switch (weather) {
    case WeatherCondition.clear:     return 100;  // 100% - Optimal conditions
    case WeatherCondition.cloudy:    return 95;   // 95%  - Slight reduction
    case WeatherCondition.rain:      return 75;   // 75%  - Reduced traction
    case WeatherCondition.heavyRain: return 50;   // 50%  - Significantly reduced
    case WeatherCondition.fog:       return 60;   // 60%  - Visibility issue
    case WeatherCondition.snow:      return 45;   // 45%  - Very slippery
    case WeatherCondition.storm:     return 40;   // 40%  - Dangerous
  }
}
```

**Explanation:**
- Each weather condition is mapped to a **percentage value (0-100)** representing the safety level
- Clear weather = 100% (no reduction applied to speed)
- Dangerous conditions like storm map to 40% (60% speed reduction)
- The mapping is based on the severity of impact on driving safety

---

### 2.2 Time of Day Mapping

**Location:** `lib/models/speed_calculator.dart:202-213`

```dart
static int _getTimeMultiplier(DayPeriod time) {
  switch (time) {
    case DayPeriod.morning:   return 90;   // 90% - Moderate traffic (5AM-12PM)
    case DayPeriod.afternoon: return 100;  // 100% - Best conditions (12PM-5PM)
    case DayPeriod.evening:   return 75;   // 75% - Reduced visibility (5PM-8PM)
    case DayPeriod.night:     return 60;   // 60% - Poor visibility (8PM-5AM)
  }
}
```

**Explanation:**
- Afternoon has the highest multiplier (100%) as it typically has best visibility
- Night driving has the lowest (60%) due to poor visibility and higher accident risk
- Morning has moderate reduction (90%) due to commute traffic

---

### 2.3 Location Type Mapping

**Location:** `lib/models/speed_calculator.dart:225-240`

```dart
static int _getLocationMultiplier(LocationType location) {
  switch (location) {
    case LocationType.highway:         return 100;  // 100% - Designed for high speed
    case LocationType.suburban:        return 85;   // 85% - Moderate speed
    case LocationType.urban:           return 70;   // 70% - City traffic
    case LocationType.residential:     return 50;   // 50% - Very low speed
    case LocationType.schoolZone:      return 30;   // 30% - Speed bumps, children
    case LocationType.constructionZone: return 40;  // 40% - Reduced speed
  }
}
```

**Explanation:**
- Highway = 100% (no reduction - roads designed for high speeds)
- School zones get the lowest (30%) due to presence of children
- Construction zones get 40% due to road work and hazards

---

### 2.4 Visibility Level Mapping

**Location:** `lib/models/speed_calculator.dart:251-264`

```dart
static int _getVisibilityMultiplier(VisibilityLevel visibility) {
  switch (visibility) {
    case VisibilityLevel.excellent: return 100;  // 100% - Optimal
    case VisibilityLevel.good:       return 90;  // 90%  - Slightly reduced
    case VisibilityLevel.moderate:   return 75;  // 75%  - Noticeably reduced
    case VisibilityLevel.poor:       return 55;  // 55%  - Significantly reduced
    case VisibilityLevel.veryPoor:   return 35;  // 35%  - Dangerous
  }
}
```

**Explanation:**
- Excellent visibility = 100% (no reduction)
- Very poor visibility = 35% (65% speed reduction)
- This maps camera brightness readings to safety percentages

---

## 3. Visibility Detection Mapping (Camera to Level)

**Location:** `lib/services/visibility_service.dart:119-131`

```dart
void _updateVisibilityLevel(double brightness) {
  if (brightness > 180) {
    _visibilityLevel = VisibilityLevel.excellent;
  } else if (brightness > 100) {
    _visibilityLevel = VisibilityLevel.good;
  } else if (brightness > 50) {
    _visibilityLevel = VisibilityLevel.moderate;
  } else if (brightness > 20) {
    _visibilityLevel = VisibilityLevel.poor;
  } else {
    _visibilityLevel = VisibilityLevel.veryPoor;
  }
}
```

**How it works:**
1. Camera captures image every 5 seconds
2. Image brightness calculated by averaging RGB pixel values
3. Brightness value (0-255) mapped to visibility level using thresholds:
   - >180 → Excellent (bright daylight)
   - 100-180 → Good (overcast)
   - 50-100 → Moderate (dusk/dawn)
   - 20-50 → Poor (heavy clouds/light fog)
   - <20 → Very Poor (dark/heavy fog)

---

## 4. Location Type Detection Mapping (GPS Speed to Location)

**Location:** `lib/services/auto_parameters_service.dart:76-88`

```dart
Future<void> updateLocationType(Position? position) async {
  if (position == null) return;
  
  final speed = position.speed * 3.6; // Convert m/s to km/h
  if (speed < 30) {
    _location = LocationType.urban;
  } else if (speed < 70) {
    _location = LocationType.suburban;
  } else {
    _location = LocationType.highway;
  }
}
```

**How it works:**
1. GPS provides speed in meters/second
2. Converted to km/h by multiplying by 3.6
3. Speed thresholds determine location type:
   - <30 km/h → Urban (stop-and-go traffic)
   - 30-70 km/h → Suburban (moderate speed)
   - >70 km/h → Highway (high speed)

---

## 5. Time of Day Detection Mapping

**Location:** `lib/services/auto_parameters_service.dart:53-65`

```dart
void updateTimeOfDay() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) {
    _timeOfDay = DayPeriod.morning;
  } else if (hour >= 12 && hour < 17) {
    _timeOfDay = DayPeriod.afternoon;
  } else if (hour >= 17 && hour < 20) {
    _timeOfDay = DayPeriod.evening;
  } else {
    _timeOfDay = DayPeriod.night;
  }
}
```

**How it works:**
1. Device clock provides current hour (0-23)
2. Hour mapped to time period:
   - 5AM-12PM → Morning
   - 12PM-5PM → Afternoon
   - 5PM-8PM → Evening
   - 8PM-5AM → Night

---

## 6. Main Calculation Algorithm

**Location:** `lib/models/speed_calculator.dart:277-354`

```dart
static SpeedCalculationResult calculate(SpeedParameters params) {
  // Step 1: Get individual multipliers
  final weatherMult = _getWeatherMultiplier(params.weather);
  final timeMult = _getTimeMultiplier(params.timeOfDay);
  final locationMult = _getLocationMultiplier(params.location);
  final visibilityMult = _getVisibilityMultiplier(params.visibility);

  // Step 2: Calculate overall multiplier as average
  // Note: Dividing by 400 because each is 0-100 (not 0-1)
  final overallMultiplier =
      (weatherMult + timeMult + locationMult + visibilityMult) / 400;

  // Step 3: Apply multiplier to base speed limit
  int recommendedSpeed = (params.baseSpeedLimit * overallMultiplier).round();
  
  // Step 4: Clamp result between min (20) and max (130) km/h
  recommendedSpeed = recommendedSpeed.clamp(minSpeed, maxSpeed);

  // Step 5: Calculate risk level (inverse of multiplier)
  final riskScore = 100 - ((overallMultiplier - 0.3) * 100).round();
  final riskLevel = riskScore.clamp(0, 100);

  // Step 6: Generate warnings based on conditions
  // ... (warning generation code)
  
  return SpeedCalculationResult(...);
}
```

### Formula Breakdown:

```
recommendedSpeed = baseSpeedLimit × overallMultiplier

Where:
  overallMultiplier = (weatherMult + timeMult + locationMult + visibilityMult) / 400

Example:
  Base speed: 60 km/h
  Weather: Clear (100) + Afternoon (100) + Urban (70) + Excellent (100) = 370
  Overall multiplier: 370 / 400 = 0.925
  
  Recommended speed: 60 × 0.925 = 55.5 → 56 km/h
```

---

## 7. Complete Example Walkthrough

### Input Parameters:
- **Weather:** Rain (75% multiplier)
- **Time:** Evening (75% multiplier)
- **Location:** Urban (70% multiplier)
- **Visibility:** Good (90% multiplier)
- **Base Speed Limit:** 60 km/h

### Calculation:

```
Step 1: Get multipliers
  weatherMult = 75
  timeMult = 75
  locationMult = 70
  visibilityMult = 90

Step 2: Calculate overall multiplier
  overallMultiplier = (75 + 75 + 70 + 90) / 400 = 310 / 400 = 0.775

Step 3: Calculate recommended speed
  recommendedSpeed = 60 × 0.775 = 46.5 → 47 km/h

Step 4: Clamp to valid range
  47 is between 20 and 130, so result = 47 km/h

Step 5: Calculate risk level
  riskScore = 100 - ((0.775 - 0.3) × 100) = 100 - 47.5 = 52.5 → 53%
  Risk level = 53 (MEDIUM)
```

### Result:
- **Recommended Speed:** 47 km/h
- **Risk Level:** 53% (MEDIUM)
- **Warnings:** "Wet roads - reduce speed to prevent hydroplaning"

---

## 8. Summary Table

| Parameter | Detection Method | Mapping Values | Impact on Speed |
|-----------|------------------|----------------|-----------------|
| Weather | Manual selection   |  40-100% | Significant |
| Time of Day | Device clock   | 60-100% | Moderate |
| Location | GPS speed inference | 30-100% | Very Significant |
| Visibility | Camera brightness | 35-100% | Significant |

---

## 9. File Structure

```
lib/
├── models/
│   └── speed_calculator.dart    # Core mapping logic (lines 175-354)
├── services/
│   ├── auto_parameters_service.dart  # Parameter detection (lines 53-88)
│   └── visibility_service.dart        # Camera brightness mapping (lines 119-131)
```

---

*Generated for DSLS (Dynamic Speed Limit System) - Technical Documentation*
