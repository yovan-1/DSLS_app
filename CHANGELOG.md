# Changelog

All notable changes to this project are documented in this file.

## [1.0.0] - 2026-05-08

### Added
- **CI/CD Pipeline**: GitHub Actions workflows for automated building and testing
  - Main workflow (`.github/workflows/flutter-ci.yml`): Runs on every push/PR
  - Release workflow (`.github/workflows/release.yml`): Runs on version tags
- **Unit Tests**: Comprehensive test suite
  - `test/unit/speed_calculator_test.dart` - Speed calculation logic
  - `test/unit/trip_data_test.dart` - Trip data models
  - `test/unit/alert_service_test.dart` - Alert service functionality

### Fixed
- **Build Performance**: Optimized Gradle settings in `android/gradle.properties`
  - Enabled Gradle daemon for faster builds
  - Enabled parallel builds
  - Enabled build caching

### Changed
- Gradle configuration for improved build speed and reliability

## Project Modifications Summary

### Build System Optimizations

| File | Change | Impact |
|------|--------|--------|
| `android/gradle.properties` | Enabled `daemon=true`, `parallel=true`, `caching=true` | Faster incremental builds |

### CI/CD Files Added

| File | Purpose |
|------|---------|
| `.github/workflows/flutter-ci.yml` | Main CI pipeline |
| `.github/workflows/release.yml` | Release automation |

### Documentation Updates

| File | Changes |
|------|---------|
| `README.md` | Added CI/CD documentation section |

## Development Workflow

### Running Builds Locally

```bash
# Clean build (recommended after changes)
flutter clean && flutter pub get && flutter build apk --debug

# Standard build
flutter build apk --debug

# Release build
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

### Running Tests

```bash
# All unit tests
flutter test test/unit/

# Specific test file
flutter test test/unit/speed_calculator_test.dart

# Widget tests
flutter test test/widget_test.dart
```

### Creating a Release

```bash
# Update version in pubspec.yaml
# Then tag and push
git tag v1.0.0
git push origin v1.0.0
```

### CI/CD Pipeline Behavior

| Event | Pipeline Action |
|-------|-----------------|
| Push to any branch | Runs analysis + tests + builds APKs |
| Pull request | Runs analysis + tests + builds APKs |
| Version tag (`v*`) | Creates GitHub Release + uploads APK |
| Manual trigger | Runs full pipeline on demand |

### Artifact Retention

| Artifact Type | Retention Period | Download Location |
|--------------|------------------|-------------------|
| Debug APK | 30 days | GitHub Actions > Artifacts |
| Release APK | 30 days | GitHub Actions > Artifacts |
| Release APK | Permanent | GitHub Releases |
