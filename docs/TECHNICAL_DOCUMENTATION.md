# Dynamic Speed Limit System (DSLS) - Technical Documentation

## Overview

The Dynamic Speed Limit System (DSLS) is a Flutter-based Android application that calculates and displays recommended driving speeds based on real-time environmental conditions. The system uses multiple data sources including GPS, camera, and device time to automatically adjust speed recommendations for optimal safety.

---

## System Architecture

### 1. Data Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   GPS Service   │───>│ AutoParameters  │───>│ Speed Calculator    │
│ (Speed/Location)│    │     Service     │    │                     │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                              ↑                         ↓
┌─────────────────┐           │              ┌─────────────────────┐
│  Visibility     │───────────┘              │   Speed Screen     │
│  (Camera)       │                          │   (User Interface) │
└─────────────────┘                          └─────────────────────┘
```

### 2. Core Components

#### A. Speed Parameters (lib/models/speed_calculator.dart)

The system calculates recommended speed based on **5 key parameters**:

| Parameter | Source | Description |
|-----------|--------|-------------|
| **Weather** | User input (manual) / API (future) | Current weather condition |
| **Time of Day** | Device clock (automatic) | Morning/Afternoon/Evening/Night |
| **Location** | GPS speed-based inference | Urban/Suburban/Highway/Residential |
| **Visibility** | Camera brightness (automatic) | Excellent to Very Poor |
| **Base Speed Limit** | User input | Default: 60 km/h |

#### B. Calculation Algorithm

The speed calculation uses a **multiplicative factor system**:

```
Recommended Speed = Base Speed Limit × Overall Multiplier

Where:
  Overall Multiplier = (Weather × Time × Location × Visibility) / 400
```

**Multiplier Values:**

| Parameter | Level | Multiplier |
|-----------|-------|------------|
| **Weather** | Clear | 100% |
| | Cloudy | 95% |
| | Rain | 75% |
| | Heavy Rain | 50% |
| | Fog | 60% |
| | Snow | 45% |
| | Storm | 40% |
| **Time of Day** | Morning (6-12) | 90% |
| | Afternoon (12-18) | 100% |
| | Evening (18-22) | 75% |
| | Night (22-6) | 60% |
| **Location** | Highway | 100% |
| | Suburban | 85% |
| | Urban | 70% |
| | Residential | 50% |
| | School Zone | 30% |
| | Construction Zone | 40% |
| **Visibility** | Excellent | 100% |
| | Good | 90% |
| | Moderate | 75% |
| | Poor | 55% |
| | Very Poor | 35% |

**Example Calculation:**
- Base limit: 60 km/h
- Clear weather (100%) + Afternoon (100%) + Urban (70%) + Excellent visibility (100%)
- Overall: (100+100+70+100)/400 = 0.925
- Recommended: 60 × 0.925 = 55.5 → **56 km/h**

---

## Services

### 1. GPS Speed Service (lib/services/gps_speed_service.dart)

**Purpose:** Track vehicle speed using GPS data.

**Features:**
- Uses GPS speed when available
- Falls back to distance/time calculation if GPS speed unavailable
- Monitors GPS signal status (active/lost)
- Updates speed in real-time

**Key Methods:**
- `startTracking()` - Start GPS monitoring
- `stopTracking()` - Stop GPS monitoring
- `checkPermission()` - Request location permissions

### 2. Auto Parameters Service (lib/services/auto_parameters_service.dart)

**Purpose:** Manage automatic parameter detection.

**Features:**
- Auto-detects time of day from device clock
- Infers location type from GPS speed
- Stores weather and visibility settings
- Provides parameters for speed calculation

**Auto-detection Logic:**
```
Time of Day:
  5 AM - 12 PM  → Morning
  12 PM - 5 PM  → Afternoon
  5 PM - 8 PM   → Evening
  8 PM - 5 AM   → Night

Location (based on speed):
  < 30 km/h     → Urban
  30-70 km/h    → Suburban
  > 70 km/h     → Highway
```

### 3. Visibility Service (lib/services/visibility_service.dart)

**Purpose:** Detect ambient visibility using camera.

**Features:**
- Uses rear camera to capture ambient light
- Calculates brightness from image pixels
- Maps brightness to visibility levels
- Updates every 5 seconds

**Brightness Mapping:**
| Brightness Value | Visibility Level |
|------------------|------------------|
| > 180 | Excellent |
| 100 - 180 | Good |
| 50 - 100 | Moderate |
| 20 - 50 | Poor |
| < 20 | Very Poor |

**Brightness Calculation:**
- Captures image from camera
- Samples pixels from the image
- Calculates average RGB value
- Maps to visibility level

---

## User Interface

### Speed Screen (lib/screens/speed_screen.dart)

**Features:**
1. **Speedometer Display**
   - Shows current speed (from GPS)
   - Shows recommended speed (calculated)
   - Color-coded border (green/yellow/red based on safety)

2. **Auto/Manual Toggle**
   - Auto mode: Uses automatic parameter detection
   - Manual mode: User can adjust base speed limit only

3. **Status Indicators**
   - GPS status (active/lost)
   - Current parameters (weather, location, visibility)

4. **Warnings Display**
   - Shows relevant safety warnings based on conditions

---

## Installation & Setup

### Prerequisites
- Flutter SDK 3.x
- Android SDK
- Android device with wireless debugging enabled

### Required Permissions (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

### Dependencies (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2
  geolocator: ^13.0.2
  permission_handler: ^11.4.0
  camera: ^0.11.1
```

---

## Risk Assessment

The system also calculates a risk level (0-100%) based on conditions:

| Risk Level | Description |
|------------|-------------|
| 70-100% | HIGH - Dangerous conditions |
| 40-70% | MEDIUM - Caution needed |
| 0-40% | LOW - Safe conditions |

---

## Future Enhancements

1. **Weather API Integration** - Fetch weather data automatically
2. **Map Integration** - Detect location type from GPS coordinates
3. **Speed Limit API** - Fetch actual road speed limits
4. **Notifications** - Alert when exceeding recommended speed
5. **Trip History** - Log trips and speed data

---

## Troubleshooting

### GPS Not Working
- Ensure location permissions are granted
- Check that GPS is enabled on device
- Verify wireless debugging connection

### Camera Not Working
- Ensure camera permission is granted
- Check that no other app is using the camera
- Verify camera hardware is functional

### App Not Building
- Run `flutter clean` to clear cache
- Run `flutter pub get` to update dependencies
- Check Android SDK is properly configured

---

## File Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── speed_calculator.dart # Speed calculation logic
├── screens/
│   ├── speed_screen.dart     # Main speed display
│   ├── alerts_screen.dart    # Speed alerts
│   └── history_screen.dart   # Trip history
├── services/
│   ├── gps_speed_service.dart      # GPS tracking
│   ├── auto_parameters_service.dart # Auto parameters
│   ├── visibility_service.dart     # Camera visibility
│   ├── alert_service.dart          # Speed alerts
│   └── trip_service.dart           # Trip tracking
└── widgets/
    └── bottom_nav.dart       # Navigation
```

---

## Contact & Support

For issues or questions, please refer to the project repository or contact the development team.