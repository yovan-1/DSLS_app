import '../models/speed_calculator.dart';

class WeatherData {
  final WeatherCondition condition;
  final double temperature;
  final double humidity;
  final double windSpeed;
  final String description;
  final DateTime timestamp;
  final String? location;

  const WeatherData({
    required this.condition,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.description,
    required this.timestamp,
    this.location,
  });

  factory WeatherData.fromWttr(Map<String, dynamic> json) {
    final current = json['current_condition'] as List?;
    if (current == null || current.isEmpty) {
      return WeatherData.defaults();
    }

    final cond = current[0] as Map<String, dynamic>;
    final weatherCode = _parseWttrInt(cond['weatherCode']);
    final tempC = double.tryParse(cond['temp_C']?.toString() ?? '0') ?? 0;
    final humidity = double.tryParse(cond['humidity']?.toString() ?? '50') ?? 50;
    final windKm = double.tryParse(cond['windspeedkm']?.toString() ?? '0') ?? 0;
    final desc = _parseWttrDescription(cond['weatherDesc']);

    final condition = _mapWeatherCode(weatherCode);

    return WeatherData(
      condition: condition,
      temperature: tempC,
      humidity: humidity,
      windSpeed: windKm,
      description: desc,
      timestamp: DateTime.now(),
    );
  }


  static int _parseWttrInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is Map) return int.tryParse(value['value']?.toString() ?? '0') ?? 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  static String _parseWttrDescription(dynamic value) {
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map) return first['value']?.toString() ?? 'Unknown';
      return first.toString();
    }
    if (value is Map) return value['value']?.toString() ?? 'Unknown';
    return value?.toString() ?? 'Unknown';
  }

  static WeatherCondition _mapWeatherCode(int code) {
    // wttr.in uses WorldWeatherOnline-style weather codes.
    switch (code) {
      case 113:
        return WeatherCondition.clear;
      case 116:
      case 119:
      case 122:
        return WeatherCondition.cloudy;
      case 143:
      case 248:
      case 260:
        return WeatherCondition.fog;
      case 176:
      case 263:
      case 266:
      case 293:
      case 296:
      case 353:
        return WeatherCondition.rain;
      case 299:
      case 302:
      case 305:
      case 308:
      case 356:
      case 359:
        return WeatherCondition.heavyRain;
      case 185:
      case 281:
      case 284:
      case 311:
      case 314:
        return WeatherCondition.freezingRain;
      case 182:
      case 317:
      case 320:
      case 362:
      case 365:
        return WeatherCondition.sleet;
      case 179:
      case 227:
      case 230:
      case 323:
      case 326:
      case 329:
      case 332:
      case 335:
      case 338:
      case 368:
      case 371:
      case 392:
      case 395:
        return WeatherCondition.snow;
      case 350:
      case 374:
      case 377:
        return WeatherCondition.hail;
      case 200:
      case 386:
      case 389:
        return WeatherCondition.storm;
    }

    // Fallback for Open-Meteo/WMO-style codes if this parser is reused later.
    if (code == 0 || code == 1) return WeatherCondition.clear;
    if (code >= 2 && code <= 3) return WeatherCondition.cloudy;
    if (code >= 45 && code <= 48) return WeatherCondition.fog;
    if (code >= 51 && code <= 67) return WeatherCondition.rain;
    if (code >= 71 && code <= 75) return WeatherCondition.snow;
    if (code == 77) return WeatherCondition.hail;
    if (code >= 80 && code <= 82) return WeatherCondition.heavyRain;
    if (code >= 85 && code <= 86) return WeatherCondition.snow;
    if (code >= 95 && code <= 99) return WeatherCondition.storm;

    return WeatherCondition.clear;
  }

  factory WeatherData.defaults() {
    return WeatherData(
      condition: WeatherCondition.clear,
      temperature: 20,
      humidity: 50,
      windSpeed: 0,
      description: 'Clear',
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'condition': condition.index,
    'temperature': temperature,
    'humidity': humidity,
    'windSpeed': windSpeed,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'location': location,
  };

  factory WeatherData.fromJson(Map<String, dynamic> json) => WeatherData(
    condition: WeatherCondition.values[json['condition'] ?? 0],
    temperature: (json['temperature'] as num?)?.toDouble() ?? 20,
    humidity: (json['humidity'] as num?)?.toDouble() ?? 50,
    windSpeed: (json['windSpeed'] as num?)?.toDouble() ?? 0,
    description: json['description'] ?? 'Unknown',
    timestamp: json['timestamp'] != null
        ? DateTime.parse(json['timestamp'])
        : DateTime.now(),
    location: json['location'],
  );

  bool get isStale {
    final now = DateTime.now();
    return now.difference(timestamp).inHours > 1;
  }

  bool get isFromCache => isStale;
}

class WeatherSource {
  static const String wttr = 'wttr';
  static const String openWeatherMap = 'openweathermap';
}

enum WeatherProviderType {
  wttr,
  openWeatherMap,
}

extension WeatherProviderTypeExtension on WeatherProviderType {
  String get displayName {
    switch (this) {
      case WeatherProviderType.wttr:
        return 'wttr.in (Auto)';
      case WeatherProviderType.openWeatherMap:
        return 'OpenWeatherMap';
    }
  }

  String get key {
    switch (this) {
      case WeatherProviderType.wttr:
        return 'wttr';
      case WeatherProviderType.openWeatherMap:
        return 'openweathermap';
    }
  }
}

class WeatherServiceConfig {
  final WeatherProviderType providerType;
  final bool isAutoMode;
  final String? apiKey;

  const WeatherServiceConfig({
    this.providerType = WeatherProviderType.wttr,
    this.isAutoMode = true,
    this.apiKey,
  });

  Map<String, dynamic> toJson() => {
    'providerType': providerType.key,
    'isAutoMode': isAutoMode,
    'apiKey': apiKey,
  };

  factory WeatherServiceConfig.fromJson(Map<String, dynamic> json) {
    final providerKey = json['providerType'] as String? ?? 'wttr';
    WeatherProviderType type;

    switch (providerKey) {
      case 'openweathermap':
        type = WeatherProviderType.openWeatherMap;
        break;
      default:
        type = WeatherProviderType.wttr;
    }

    return WeatherServiceConfig(
      providerType: type,
      isAutoMode: json['isAutoMode'] as bool? ?? true,
      apiKey: json['apiKey'] as String?,
    );
  }
}