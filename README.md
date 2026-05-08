# Dynamic Speed Limit System (DSLS)

A Flutter-based Android application that calculates and displays recommended driving speeds based on real-time environmental conditions.

## Team

### Supervisor
- Dr. Adones Rukundo

### Members
| Name | Index Number |
|------|---------------|
| WASIKE HANANI ELIZABETH | 2023/BSE/148/PS |
| OKELLO DAVID | 2023/BSE/127/PS |
| IKAYO EMMANUEL | 2023/BSE/050/PS |
| AINOMUJUNI YOVAN | 2023/BSE/158/PS |
| MUWONGE STUART | 2023/BSE/097/PS |

## Features

- **Real-time Speed Monitoring**: Uses GPS to track current vehicle speed
- **Dynamic Speed Recommendations**: Calculates safe speed based on multiple factors:
  - Weather conditions (Clear, Cloudy, Rain, Heavy Rain, Fog, Snow, Storm)
  - Time of day (Morning, Afternoon, Evening, Night)
  - Location type (Urban, Suburban, Highway, Residential, School Zone, Construction Zone)
  - Visibility (detected via camera brightness)
- **Auto/Manual Mode**: Toggle between automatic parameter detection and manual configuration
- **Safety Alerts**: Warns about dangerous driving conditions
- **GPS Status**: Monitors GPS signal health

## Installation

### Prerequisites
- Flutter SDK 3.x
- Android SDK
- Android device with wireless debugging enabled

### Required Permissions
- Location (fine and coarse)
- Camera
- Internet

### Build & Install
```bash
# Get dependencies
flutter pub get

# Build debug APK
flutter build apk --debug

# Install on device (ensure ADB connected)
flutter install
```

## How It Works

The app uses a multiplicative factor system to calculate recommended speed:

```
Recommended Speed = Base Speed Limit × (Weather% + Time% + Location% + Visibility%) / 400
```

Each parameter gets a percentage based on current conditions:
- Clear weather = 100%, Heavy rain = 50%, Storm = 40%
- Afternoon = 100%, Night = 60%
- Highway = 100%, School Zone = 30%
- Excellent visibility = 100%, Very Poor = 35%

## Technical Details

See [TECHNICAL_DOCUMENTATION.md](docs/TECHNICAL_DOCUMENTATION.md) for detailed technical information.

### Key Services
- **GPS Speed Service**: Tracks vehicle speed using GPS
- **Visibility Service**: Detects ambient light using camera
- **Auto Parameters Service**: Manages automatic parameter detection
- **Speed Calculator**: Core calculation logic

## Project Structure
```
lib/
├── main.dart
├── models/
│   └── speed_calculator.dart
├── screens/
│   ├── speed_screen.dart
│   ├── alerts_screen.dart
│   └── history_screen.dart
├── services/
│   ├── gps_speed_service.dart
│   ├── auto_parameters_service.dart
│   ├── visibility_service.dart
│   ├── alert_service.dart
│   └── trip_service.dart
└── widgets/
    └── bottom_nav.dart
```

## CI/CD Pipeline

This project uses GitHub Actions for continuous integration and continuous deployment.

### Workflows

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| Main CI | `.github/workflows/flutter-ci.yml` | Push to any branch, PR | Build & test on every change |
| Release | `.github/workflows/release.yml` | Version tags (`v*`) | Create releases with APKs |

### Main CI Workflow (`flutter-ci.yml`)

The main workflow runs on every push and pull request to ensure code quality:

```
┌─────────────────┐
│  Analyze & Test │  (Parallel jobs)
├─────────────────┤
│ • flutter analyze --fatal-infos --fatal-warnings
│ • flutter test test/unit/
│ • flutter test test/widget_test.dart
└────────┬────────┘
         │ (on success)
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐ ┌──────────┐
│ Debug │ │ Release  │
│  APK  │ │   APK    │
└───┬───┘ └────┬─────┘
    │           │
    ▼           ▼
┌─────────┐ ┌────────────┐
│ Artifact│ │  Artifact  │
│ (30 days)│ │ (30 days) │
└─────────┘ └────────────┘
```

### Release Workflow (`release.yml`)

Triggered when pushing version tags (e.g., `v1.0.0`):

```bash
# Create a release
git tag v1.0.0
git push origin v1.0.0
```

This creates:
- Draft GitHub Release
- Release APK uploaded to the release

### Build Artifacts

| Type | Retention | Access |
|------|-----------|--------|
| Debug APK | 30 days | GitHub Actions > Artifacts |
| Release APK | 30 days | GitHub Actions > Artifacts |
| Release APK | Permanent | GitHub Releases |

### Requirements

- **Static Analysis**: All code must pass `flutter analyze` with no warnings or infos
- **Tests**: All unit tests must pass before building
- **Builds**: Both debug and release APKs are built automatically

### Status Badges

Add to your README after pushing:

```markdown
[![Flutter CI](https://github.com/yovan-1/DSLS_app_refined_v6_no_sidebar/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/yovan-1/DSLS_app_refined_v6_no_sidebar/actions/workflows/flutter-ci.yml)
```

## License
MIT License