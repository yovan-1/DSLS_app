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

## Future Enhancements
- Weather API integration
- Map integration for location detection
- Speed limit API integration
- Speed violation notifications
- Trip history logging

## License
MIT License