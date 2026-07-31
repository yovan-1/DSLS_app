import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_data.dart';
import '../models/trip_data.dart';

class OfflineStorageService {
  static const String _keyWeatherData = 'offline_weather_data';
  static const String _keyWeatherConfig = 'weather_service_config';
  static const String _keyTripData = 'trip_data';
  static const String _keyLastLocation = 'last_location';
  static const String _keyUserPreferences = 'user_preferences';

  /// Everything this service owns. `last_location` is stored as two doubles
  /// under suffixed keys, so both are listed.
  static const List<String> _ownedKeys = [
    _keyWeatherData,
    _keyWeatherConfig,
    _keyTripData,
    '${_keyLastLocation}_lat',
    '${_keyLastLocation}_lon',
    _keyUserPreferences,
  ];

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> cacheWeatherData(WeatherData data) async {
    try {
      final json = jsonEncode(data.toJson());
      await _prefs?.setString(_keyWeatherData, json);
      debugPrint('[OfflineStorage] Weather data cached');
    } catch (e) {
      debugPrint('[OfflineStorage] Error caching weather: $e');
    }
  }

  Future<WeatherData?> getCachedWeatherData() async {
    try {
      final json = _prefs?.getString(_keyWeatherData);
      if (json == null) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      return WeatherData.fromJson(data);
    } catch (e) {
      debugPrint('[OfflineStorage] Error getting cached weather: $e');
      return null;
    }
  }

  Future<void> saveWeatherConfig(WeatherServiceConfig config) async {
    try {
      final json = jsonEncode(config.toJson());
      await _prefs?.setString(_keyWeatherConfig, json);
    } catch (e) {
      debugPrint('[OfflineStorage] Error saving weather config: $e');
    }
  }

  Future<WeatherServiceConfig?> getWeatherConfig() async {
    try {
      final json = _prefs?.getString(_keyWeatherConfig);
      if (json == null) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      return WeatherServiceConfig.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveTrips(List<TripData> trips) async {
    try {
      final json = jsonEncode(trips.map((t) => t.toJson()).toList());
      await _prefs?.setString(_keyTripData, json);
      debugPrint('[OfflineStorage] ${trips.length} trips saved');
    } catch (e) {
      debugPrint('[OfflineStorage] Error saving trips: $e');
    }
  }

  Future<List<TripData>> getTrips() async {
    try {
      final json = _prefs?.getString(_keyTripData);
      if (json == null) return [];

      final list = jsonDecode(json) as List;
      return list.map((t) => TripData.fromJson(t as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[OfflineStorage] Error getting trips: $e');
      return [];
    }
  }

  Future<void> saveLastLocation(double lat, double lon) async {
    try {
      await _prefs?.setDouble('${_keyLastLocation}_lat', lat);
      await _prefs?.setDouble('${_keyLastLocation}_lon', lon);
    } catch (e) {
      debugPrint('[OfflineStorage] Error saving location: $e');
    }
  }

  Future<Map<String, double>?> getLastLocation() async {
    try {
      final lat = _prefs?.getDouble('${_keyLastLocation}_lat');
      final lon = _prefs?.getDouble('${_keyLastLocation}_lon');
      if (lat == null || lon == null) return null;
      return {'lat': lat, 'lon': lon};
    } catch (e) {
      return null;
    }
  }

  Future<void> saveUserPreferences(Map<String, dynamic> prefs) async {
    try {
      final json = jsonEncode(prefs);
      await _prefs?.setString(_keyUserPreferences, json);
    } catch (e) {
      debugPrint('[OfflineStorage] Error saving preferences: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserPreferences() async {
    try {
      final json = _prefs?.getString(_keyUserPreferences);
      if (json == null) return null;
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Clears only this service's keys.
  ///
  /// This used to call `_prefs.clear()`, which wipes *every* preference in the
  /// app — alert settings, the first-launch flag, the wakelock preference and
  /// the auto-upload flag included. Clearing offline caches should not log the
  /// user back through the first-run disclaimer.
  Future<void> clearAll() async {
    try {
      for (final key in _ownedKeys) {
        await _prefs?.remove(key);
      }
      debugPrint('[OfflineStorage] Offline data cleared');
    } catch (e) {
      debugPrint('[OfflineStorage] Error clearing: $e');
    }
  }

  Future<bool> isOfflineDataAvailable() async {
    final weather = await getCachedWeatherData();
    return weather != null && !weather.isStale;
  }
}