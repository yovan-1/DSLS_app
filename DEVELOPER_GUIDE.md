# Developer Guide: DSLS App Parameter Configuration

This document guides team members on how to clone the repository and modify the core parameters (Location, Speed, Time, Visibility) in the code.

---

## 1. Cloning the Repository

### Prerequisites
- Git installed on your machine
- Flutter SDK (version 3.x or higher)
- A code editor (VS Code, Android Studio, or IntelliJ)

### Steps to Clone

1. **Open your terminal** and navigate to your desired workspace directory:
   ```bash
   cd ~/your_workspace_folder
   ```

2. **Clone the repository**:
   ```bash
   git clone https://github.com/your-org/dsls_app.git
   ```
   > Replace `your-org` with the actual GitHub organization or username.

3. **Navigate into the project**:
   ```bash
   cd DSLS_app
   ```

4. **Install dependencies**:
   ```bash
   flutter pub get
   ```

5. **Verify the setup** by running the app:
   ```bash
   flutter run
   ```

---

## 2. Project Structure Overview

The key files for parameter configuration are located in:

| File | Purpose |
|------|---------|
| `lib/models/speed_calculator.dart` | Contains all enums and calculation logic |
| `lib/services/auto_parameters_service.dart` | Central service managing all parameters |
| `lib/services/gps_speed_service.dart` | GPS-based speed tracking |
| `lib/services/visibility_service.dart` | Camera-based visibility detection |

---

## 3. Modifying Parameters

### 3.1 Location Type

**File:** `lib/models/speed_calculator.dart` (lines 44-64)

Location types are defined in the `LocationType` enum:
```dart
enum LocationType {
  highway,
  suburban,
  urban,
  residential,
  schoolZone,
  constructionZone,
}
```

**To modify the location multiplier** (affects speed calculation), edit the `_getLocationMultiplier` method in `lib/models/speed_calculator.dart` (lines 225-240):
```dart
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
  }
}
```

**To change automatic location detection**, edit `updateLocationType` in `lib/services/auto_parameters_service.dart` (lines 76-88):
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
  notifyListeners();
}
```
- **Speed thresholds:** Change `30` and `70` to adjust when the app switches between urban, suburban, and highway.

---

### 3.2 Speed

**File:** `lib/models/speed_calculator.dart` (lines 145-354)

**To modify the speed calculation algorithm**, edit the `SpeedCalculator.calculate` method.

**To change min/max speed limits**, edit the constants in `lib/models/speed_calculator.dart` (lines 158-162):
```dart
static const int minSpeed = 20;   // Minimum recommended speed in km/h
static const int maxSpeed = 130;  // Maximum recommended speed in km/h
```

**To modify weather multipliers** (affects speed), edit `_getWeatherMultiplier` (lines 175-192):
```dart
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
    case WeatherCondition.storm:
      return 40;
  }
}
```

**To modify base speed limit**, edit `lib/services/auto_parameters_service.dart` (line 125):
```dart
baseSpeedLimit: 60, // Default base limit in km/h - change this value
```

---

### 3.3 Time of Day

**File:** `lib/models/speed_calculator.dart` (lines 28-42)

Time periods are defined in the `DayPeriod` enum:
```dart
enum DayPeriod {
  morning,   // 6 AM - 12 PM
  afternoon, // 12 PM - 6 PM
  evening,   // 6 PM - 10 PM
  night,     // 10 PM - 6 AM
}
```

**To modify time detection logic**, edit `updateTimeOfDay` in `lib/services/auto_parameters_service.dart` (lines 53-65):
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
  notifyListeners();
}
```
- Change the hour ranges (e.g., `5`, `12`, `17`, `20`) to customize time period detection.

**To modify time multipliers**, edit `_getTimeMultiplier` in `lib/models/speed_calculator.dart` (lines 202-213):
```dart
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
```

---

### 3.4 Visibility

**File:** `lib/models/speed_calculator.dart` (lines 66-83)

Visibility levels are defined in the `VisibilityLevel` enum:
```dart
enum VisibilityLevel {
  excellent,  // >180 brightness
  good,       // 100-180 brightness
  moderate,   // 50-100 brightness
  poor,       // 20-50 brightness
  veryPoor,   // <20 brightness
}
```

**To modify brightness thresholds**, edit `_updateVisibilityLevel` in `lib/services/visibility_service.dart` (lines 119-131):
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
- Change the threshold values (180, 100, 50, 20) to adjust visibility detection sensitivity.

**To modify visibility capture interval**, edit in `lib/services/visibility_service.dart` (line 90):
```dart
_brightnessTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
```
- Change `5` to adjust how often the camera captures images for visibility detection.

**To modify visibility multipliers**, edit `_getVisibilityMultiplier` in `lib/models/speed_calculator.dart` (lines 251-264):
```dart
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
```

---

## 3.5 Release Signing

Local release builds (`flutter build apk --release`, `flutter install --release`) are signed with a real, private keystore at `android/app/upload-keystore.jks`, configured via `android/key.properties` (both gitignored — never commit them). If you need to generate your own for a fresh clone:

```bash
keytool -genkeypair -v -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties`:
```
storePassword=<your password>
keyPassword=<your password>
keyAlias=upload
storeFile=upload-keystore.jks
```

If `android/key.properties` is absent (e.g. in CI), `build.gradle.kts` falls back to the debug keystore and logs a warning — CI-built release APKs are **not** production-signed unless the keystore/passwords are added as GitHub Actions secrets and the workflow is updated to write them out before building.

---

## 4. Making and Submitting Changes

### Workflow

1. **Create a new branch** for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your modifications** in the relevant files.

3. **Test your changes**:
   ```bash
   flutter analyze       # Check for issues
   flutter test          # Run unit tests
   flutter run           # Test on device/emulator
   ```

4. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Description of your changes"
   ```

5. **Push to GitHub**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request** on GitHub for team review.

---

## 5. Quick Reference Table

| Parameter | Enum Location | Multiplier Location | Detection Logic Location |
|-----------|---------------|---------------------|-------------------------|
| Location | `speed_calculator.dart:44-64` | `speed_calculator.dart:225-240` | `auto_parameters_service.dart:76-88` |
| Speed | `speed_calculator.dart:158-162` | `speed_calculator.dart:175-264` | `speed_calculator.dart:277-354` |
| Time | `speed_calculator.dart:28-42` | `speed_calculator.dart:202-213` | `auto_parameters_service.dart:53-65` |
| Visibility | `speed_calculator.dart:66-83` | `speed_calculator.dart:251-264` | `visibility_service.dart:119-131` |

---

## 6. Testing Your Changes

Run the existing unit tests to ensure your changes don't break anything:
```bash
flutter test
```

To add new test cases, see `test/unit/` directory for examples.

---

For questions or issues, contact the project maintainer or open an issue on GitHub.
