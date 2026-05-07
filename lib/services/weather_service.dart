import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/weather_data.dart';
import '../models/speed_calculator.dart';

abstract class WeatherService {
  Future<WeatherData> getWeather(double latitude, double longitude);

  Future<WeatherData> getWeatherByLocation(String location);

  bool get isEnabled;

  String get providerName;
}

class WttrInWeatherService implements WeatherService {
  static const String _baseUrl = 'https://wttr.in';

  @override
  bool get isEnabled => true;

  @override
  String get providerName => 'wttr.in';

  @override
  Future<WeatherData> getWeather(double latitude, double longitude) async {
    try {
      final url = '$_baseUrl/${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}?format=j1';
      debugPrint('[WeatherService] Fetching weather from $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final weather = WeatherData.fromWttr(json);
        debugPrint('[WeatherService] Weather: ${weather.condition}, ${weather.temperature}°C');
        return weather;
      } else {
        debugPrint('[WeatherService] Error: ${response.statusCode}');
        return WeatherData.defaults();
      }
    } catch (e) {
      debugPrint('[WeatherService] Exception: $e');
      return WeatherData.defaults();
    }
  }

  @override
  Future<WeatherData> getWeatherByLocation(String location) async {
    try {
      final url = '$_baseUrl/$location?format=j1';
      debugPrint('[WeatherService] Fetching weather for $location');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final weather = WeatherData.fromWttr(json);
        return weather;
      } else {
        return WeatherData.defaults();
      }
    } catch (e) {
      debugPrint('[WeatherService] Exception: $e');
      return WeatherData.defaults();
    }
  }
}

class OpenWeatherMapWeatherService implements WeatherService {
  final String apiKey;

  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5/weather';

  OpenWeatherMapWeatherService({required this.apiKey});

  @override
  bool get isEnabled => apiKey.isNotEmpty;

  @override
  String get providerName => 'OpenWeatherMap';

  @override
  Future<WeatherData> getWeather(double latitude, double longitude) async {
    if (!isEnabled) {
      return WeatherData.defaults();
    }

    try {
      final url = '$_baseUrl?lat=$latitude&lon=$longitude&appid=$apiKey&units=metric';
      debugPrint('[OpenWeatherMap] Fetching weather');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return _parseWeather(json);
      } else {
        debugPrint('[OpenWeatherMap] Error: ${response.statusCode}');
        return WeatherData.defaults();
      }
    } catch (e) {
      debugPrint('[OpenWeatherMap] Exception: $e');
      return WeatherData.defaults();
    }
  }

  @override
  Future<WeatherData> getWeatherByLocation(String location) async {
    if (!isEnabled) {
      return WeatherData.defaults();
    }

    try {
      final url = '$_baseUrl?q=$location&appid=$apiKey&units=metric';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return _parseWeather(json);
      } else {
        return WeatherData.defaults();
      }
    } catch (e) {
      return WeatherData.defaults();
    }
  }

  WeatherData _parseWeather(Map<String, dynamic> json) {
    final weather = json['weather'] as List?;
    final main = json['main'] as Map<String, dynamic>?;
    final wind = json['wind'] as Map<String, dynamic>?;

    final weatherCode = weather?.isNotEmpty == true
        ? int.tryParse(weather![0]['id']?.toString() ?? '0') ?? 0
        : 0;
    final temp = (main?['temp'] as num?)?.toDouble() ?? 20;
    final humidity = (main?['humidity'] as num?)?.toDouble() ?? 50;
    final windSpeed = (wind?['speed'] as num?)?.toDouble() ?? 0;
    final desc = weather?.isNotEmpty == true ? weather![0]['description'] ?? 'Unknown' : 'Unknown';

    WeatherCondition condition;
    if (weatherCode >= 200 && weatherCode < 300) {
      condition = WeatherCondition.storm;
    } else if (weatherCode == 511) {
      condition = WeatherCondition.freezingRain;
    } else if ((weatherCode >= 502 && weatherCode <= 504) ||
        (weatherCode >= 522 && weatherCode <= 531)) {
      condition = WeatherCondition.heavyRain;
    } else if ((weatherCode >= 300 && weatherCode < 600) ||
        (weatherCode >= 520 && weatherCode <= 521)) {
      condition = WeatherCondition.rain;
    } else if (weatherCode >= 600 && weatherCode < 700) {
      condition = WeatherCondition.snow;
    } else if (weatherCode == 701 || weatherCode == 741) {
      condition = WeatherCondition.fog;
    } else if (weatherCode == 721) {
      condition = WeatherCondition.haze;
    } else if (weatherCode == 731 || weatherCode == 761) {
      condition = WeatherCondition.dust;
    } else if (weatherCode == 711) {
      condition = WeatherCondition.smoke;
    } else if (weatherCode == 800) {
      condition = WeatherCondition.clear;
    } else if (weatherCode > 800) {
      condition = WeatherCondition.cloudy;
    } else {
      condition = WeatherCondition.clear;
    }

    return WeatherData(
      condition: condition,
      temperature: temp,
      humidity: humidity,
      windSpeed: windSpeed * 3.6,
      description: desc.toString(),
      timestamp: DateTime.now(),
    );
  }
}

class WeatherServiceFactory {
  static WeatherService create(WeatherProviderType type, {String? apiKey}) {
    switch (type) {
      case WeatherProviderType.wttr:
        return WttrInWeatherService();
      case WeatherProviderType.openWeatherMap:
        return OpenWeatherMapWeatherService(apiKey: apiKey ?? '');
    }
  }
}