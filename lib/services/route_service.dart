import 'package:flutter/material.dart' hide DayPeriod;
import '../models/speed_calculator.dart';

class RouteRecommendation {
  final String id;
  final String name;
  final String description;
  final double distance;
  final int estimatedTime;
  final RouteType type;
  final int safetyScore;
  final List<String> benefits;

  RouteRecommendation({
    required this.id,
    required this.name,
    required this.description,
    required this.distance,
    required this.estimatedTime,
    required this.type,
    required this.safetyScore,
    required this.benefits,
  });
}

enum RouteType { fastest, safest, scenic, alternative }

class RouteService extends ChangeNotifier {
  LocationType _currentLocation = LocationType.urban;
  WeatherCondition _weather = WeatherCondition.clear;
  DayPeriod _timeOfDay = DayPeriod.afternoon;

  LocationType get currentLocation => _currentLocation;
  WeatherCondition get weather => _weather;
  DayPeriod get timeOfDay => _timeOfDay;

  void updateLocation(LocationType location) {
    _currentLocation = location;
    notifyListeners();
  }

  void updateWeather(WeatherCondition weather) {
    _weather = weather;
    notifyListeners();
  }

  void updateTimeOfDay(DayPeriod time) {
    _timeOfDay = time;
    notifyListeners();
  }

  List<RouteRecommendation> getRecommendations() {
    List<RouteRecommendation> routes = [];

    routes.add(
      RouteRecommendation(
        id: '1',
        name: 'Main Highway Route',
        description: 'Via Highway 1 - Best for current conditions',
        distance: 12.5,
        estimatedTime: 18,
        type: RouteType.fastest,
        safetyScore: _calculateSafetyScore(),
        benefits: ['Fastest route', 'Good visibility', 'Well maintained'],
      ),
    );

    routes.add(
      RouteRecommendation(
        id: '2',
        name: 'Local Road Alternative',
        description: 'Via City Roads - Avoids highway tolls',
        distance: 14.2,
        estimatedTime: 25,
        type: RouteType.safest,
        safetyScore: _calculateSafetyScore() + 10,
        benefits: ['Lower speed limit', 'More rest stops', 'Better lighting'],
      ),
    );

    if (_weather == WeatherCondition.rain || _weather == WeatherCondition.fog) {
      routes.add(
        RouteRecommendation(
          id: '3',
          name: 'Weather Safe Route',
          description: 'Via Covered Roads - Best in bad weather',
          distance: 16.8,
          estimatedTime: 30,
          type: RouteType.safest,
          safetyScore: _calculateSafetyScore() + 20,
          benefits: ['Covered sections', 'Better drainage', 'Less exposed'],
        ),
      );
    }

    if (_timeOfDay == DayPeriod.night) {
      routes.add(
        RouteRecommendation(
          id: '4',
          name: 'Well Lit Route',
          description: 'Via Main Streets - Best for night driving',
          distance: 13.5,
          estimatedTime: 22,
          type: RouteType.safest,
          safetyScore: _calculateSafetyScore() + 15,
          benefits: ['Street lights', 'More traffic', 'Emergency access'],
        ),
      );
    }

    routes.sort((a, b) => b.safetyScore.compareTo(a.safetyScore));

    return routes;
  }

  int _calculateSafetyScore() {
    int score = 70;

    switch (_currentLocation) {
      case LocationType.highway:
        score += 20;
        break;
      case LocationType.suburban:
        score += 5;
        break;
      case LocationType.urban:
        score -= 10;
        break;
      case LocationType.residential:
        score -= 12;
        break;
      case LocationType.schoolZone:
        score -= 20;
        break;
      case LocationType.constructionZone:
        score -= 15;
        break;
      case LocationType.roundabout:
      case LocationType.junction:
        score -= 18;
        break;
    }

    switch (_weather) {
      case WeatherCondition.clear:
        score += 15;
        break;
      case WeatherCondition.cloudy:
        score += 10;
        break;
      case WeatherCondition.rain:
        score -= 10;
        break;
      case WeatherCondition.heavyRain:
        score -= 25;
        break;
      case WeatherCondition.fog:
        score -= 20;
        break;
      case WeatherCondition.snow:
        score -= 30;
        break;
      case WeatherCondition.freezingRain:
        score -= 35;
        break;
      case WeatherCondition.sleet:
        score -= 30;
        break;
      case WeatherCondition.hail:
        score -= 40;
        break;
      case WeatherCondition.smoke:
        score -= 25;
        break;
      case WeatherCondition.dust:
        score -= 20;
        break;
      case WeatherCondition.haze:
        score -= 15;
        break;
      case WeatherCondition.storm:
        score -= 35;
        break;
    }

    switch (_timeOfDay) {
      case DayPeriod.afternoon:
        score += 10;
        break;
      case DayPeriod.morning:
        score += 5;
        break;
      case DayPeriod.evening:
        score -= 5;
        break;
      case DayPeriod.night:
        score -= 15;
        break;
    }

    return score.clamp(0, 100);
  }

  Map<String, dynamic> toJson() => {
    'location': _currentLocation.index,
    'weather': _weather.index,
    'timeOfDay': _timeOfDay.index,
  };

  void loadFromJson(Map<String, dynamic> json) {
    _currentLocation = LocationType.values[json['location'] ?? 0];
    _weather = WeatherCondition.values[json['weather'] ?? 0];
    _timeOfDay = DayPeriod.values[json['timeOfDay'] ?? 1];
    notifyListeners();
  }
}
