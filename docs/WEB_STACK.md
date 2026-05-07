# DSLS Web Stack Documentation

## Overview

The Dynamic Speed Limit System (DSLS) is built using **Flutter** as its primary framework, which enables cross-platform deployment to Android, iOS, and Web from a single codebase. This document outlines the web stack components and architecture.

---

## Technology Stack

### Core Framework

| Component | Technology | Version |
|-----------|------------|---------|
| Framework | Flutter | 3.x |
| Language | Dart | ^3.7.2 |
| State Management | Provider | ^6.1.2 |

### Web Deployment

| Component | Technology | Purpose |
|-----------|------------|---------|
| Web Renderer | CanvasKit (WASM) | High-performance rendering |
| Entry Point | web/index.html | HTML shell for Flutter web app |
| Build Output | flutter_bootstrap.js | Compiled Dart JavaScript bundle |
| Base Href | `$FLUTTER_BASE_HREF` | Configurable deployment path |

### Key Dependencies (Web-Compatible)

| Package | Version | Purpose |
|---------|---------|---------|
| provider | ^6.1.2 | State management |
| http | ^1.4.0 | HTTP requests |
| shared_preferences | ^2.2.0 | Local storage |
| fl_chart | ^0.70.0 | Charts/visualizations |
| flutter_map | ^6.0.0 | Map display |
| latlong2 | ^0.9.0 | Geographic coordinates |

### Platform-Specific (Not Web-Compatible)

These packages work on mobile but may have limited/no web support:
- `geolocator` - GPS location (limited web support)
- `camera` - Camera access (not available on web)
- `permission_handler` - Runtime permissions (mobile only)
- `vibration` - Haptic feedback (mobile only)
- `audioplayers` - Audio playback (limited web support)

---

## Architecture

### Web Build Process

```
1. Flutter compiles Dart to JavaScript (dart2js)
2. Generates flutter_bootstrap.js
3. HTML shell loads bootstrapper
4. CanvasKit (WebAssembly) renders UI
```

### Directory Structure

```
web/
├── index.html          # Web entry point
├── manifest.json       # PWA manifest
├── favicon.png         # Favicon
└── icons/              # App icons (192px, 512px)
```

### Web Configuration (index.html)

- Base href: `$FLUTTER_BASE_HREF` (replaced at build time)
- Meta tags: Mobile web app capable
- PWA support: manifest.json

---

## PWA Features

The web app supports Progressive Web App features:

| Feature | Implementation |
|---------|----------------|
| App Shell | Pre-loaded via service worker |
| Offline Support | Cache-first strategy |
| Installable | manifest.json with icons |
| Responsive | Flutter responsive widgets |

### manifest.json Configuration

- Name: "dsls_app"
- Theme color: System default
- Display: Standalone
- Icons: 192px and 512px

---

## Building for Web

### Commands

```bash
# Development server
flutter run -d chrome

# Production build
flutter build web --release

# With base href
flutter build web --release --base-href /dsls/
```

### Build Output

```
build/
└── web/
    ├── index.html
    ├── flutter_bootstrap.js
    ├── manifest.json
    └── assets/
```

---

## Web Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| GPS Speed | Limited | Requires browser geolocation API |
| Camera Visibility | Not Available | Camera not accessible in browser |
| Vibration Alerts | Not Available | No vibration API |
| Push Notifications | Not Implemented | Future enhancement |

### Fallback Behavior

- **GPS Speed**: Uses browser Geolocation API if available
- **Visibility**: Defaults to "Excellent" when camera unavailable
- **Location Type**: Falls back to manual selection

---

## Performance Considerations

| Aspect | Optimization |
|--------|--------------|
| Initial Load | Code splitting enabled |
| Rendering | CanvasKit WebAssembly |
| Bundle Size | Tree shaking via dart2js |

---

## Future Web Enhancements

1. Service Worker for offline support
2. Push notifications via Web Push API
3. Background sync for trip data
4. IndexedDB for local data persistence