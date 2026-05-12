import '../models/speed_calculator.dart';

class TripData {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final LocationType location;
  final int baseSpeedLimit;
  final int recommendedSpeed;
  final int maxSpeed;
  final int avgSpeed;
  final int overSpeedCount;
  final List<SpeedAlert> alerts;
  final String? roadSegmentId;
  final int? actualSpeedLimit;
  final String? estimatedSurface;
  final double avgRiskScore;
  final int distanceTraveledMeters;

  TripData({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.location,
    required this.baseSpeedLimit,
    required this.recommendedSpeed,
    this.maxSpeed = 0,
    this.avgSpeed = 0,
    this.overSpeedCount = 0,
    this.alerts = const [],
    this.roadSegmentId,
    this.actualSpeedLimit,
    this.estimatedSurface,
    this.avgRiskScore = 0.0,
    this.distanceTraveledMeters = 0,
  });

  TripData copyWith({
    DateTime? endTime,
    int? maxSpeed,
    int? avgSpeed,
    int? overSpeedCount,
    List<SpeedAlert>? alerts,
    String? roadSegmentId,
    int? actualSpeedLimit,
    String? estimatedSurface,
    double? avgRiskScore,
    int? distanceTraveledMeters,
  }) {
    return TripData(
      id: id,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      location: location,
      baseSpeedLimit: baseSpeedLimit,
      recommendedSpeed: recommendedSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      overSpeedCount: overSpeedCount ?? this.overSpeedCount,
      alerts: alerts ?? this.alerts,
      roadSegmentId: roadSegmentId ?? this.roadSegmentId,
      actualSpeedLimit: actualSpeedLimit ?? this.actualSpeedLimit,
      estimatedSurface: estimatedSurface ?? this.estimatedSurface,
      avgRiskScore: avgRiskScore ?? this.avgRiskScore,
      distanceTraveledMeters: distanceTraveledMeters ?? this.distanceTraveledMeters,
    );
  }

  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }

  String get formattedDuration {
    final d = duration;
    if (d == null) return 'In progress';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'location': location.index,
    'baseSpeedLimit': baseSpeedLimit,
    'recommendedSpeed': recommendedSpeed,
    'maxSpeed': maxSpeed,
    'avgSpeed': avgSpeed,
    'overSpeedCount': overSpeedCount,
    'alerts': alerts.map((a) => a.toJson()).toList(),
    'roadSegmentId': roadSegmentId,
    'actualSpeedLimit': actualSpeedLimit,
    'estimatedSurface': estimatedSurface,
    'avgRiskScore': avgRiskScore,
    'distanceTraveledMeters': distanceTraveledMeters,
  };

  factory TripData.fromJson(Map<String, dynamic> json) => TripData(
    id: json['id'],
    startTime: DateTime.parse(json['startTime']),
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    location: LocationType.values[json['location']],
    baseSpeedLimit: json['baseSpeedLimit'],
    recommendedSpeed: json['recommendedSpeed'],
    maxSpeed: json['maxSpeed'] ?? 0,
    avgSpeed: json['avgSpeed'] ?? 0,
    overSpeedCount: json['overSpeedCount'] ?? 0,
    alerts:
        (json['alerts'] as List?)
            ?.map((a) => SpeedAlert.fromJson(a))
            .toList() ??
        [],
    roadSegmentId: json['roadSegmentId'],
    actualSpeedLimit: json['actualSpeedLimit'],
    estimatedSurface: json['estimatedSurface'],
    avgRiskScore: (json['avgRiskScore'] ?? 0.0).toDouble(),
    distanceTraveledMeters: json['distanceTraveledMeters'] ?? 0,
  );
}

class SpeedAlert {
  final String id;
  final DateTime time;
  final int speed;
  final int recommendedSpeed;
  final AlertType type;

  SpeedAlert({
    required this.id,
    required this.time,
    required this.speed,
    required this.recommendedSpeed,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'speed': speed,
    'recommendedSpeed': recommendedSpeed,
    'type': type.index,
  };

  factory SpeedAlert.fromJson(Map<String, dynamic> json) => SpeedAlert(
    id: json['id'],
    time: DateTime.parse(json['time']),
    speed: json['speed'],
    recommendedSpeed: json['recommendedSpeed'],
    type: AlertType.values[json['type']],
  );
}

enum AlertType { overSpeed, harshBrake, rapidAcceleration, fatigueWarning }

class DrivingScore {
  final int overall;
  final int speedCompliance;
  final int smoothness;
  final int attention;

  const DrivingScore({
    required this.overall,
    required this.speedCompliance,
    required this.smoothness,
    required this.attention,
  });

  String get grade {
    if (overall >= 90) return 'A+';
    if (overall >= 80) return 'A';
    if (overall >= 70) return 'B';
    if (overall >= 60) return 'C';
    if (overall >= 50) return 'D';
    return 'F';
  }

  String get description {
    if (overall >= 80) return 'Excellent driving';
    if (overall >= 60) return 'Good driving';
    if (overall >= 40) return 'Needs improvement';
    return 'Poor driving';
  }

  static DrivingScore calculate(List<TripData> trips) {
    if (trips.isEmpty) {
      return const DrivingScore(
        overall: 0,
        speedCompliance: 0,
        smoothness: 0,
        attention: 0,
      );
    }

    int totalOverSpeed = 0;
    int totalAlerts = 0;
    for (final trip in trips) {
      totalOverSpeed += trip.overSpeedCount;
      totalAlerts += trip.alerts.length;
    }

    int speedCompliance = 100 - (totalOverSpeed * 5).clamp(0, 50);
    int smoothness = 100 - (totalAlerts * 3).clamp(0, 40);
    int attention =
        (trips.any((t) => t.duration != null && t.duration!.inHours > 2)
            ? 70
            : 90);

    int overall =
        ((speedCompliance * 0.4) + (smoothness * 0.4) + (attention * 0.2))
            .round();

    return DrivingScore(
      overall: overall.clamp(0, 100),
      speedCompliance: speedCompliance,
      smoothness: smoothness,
      attention: attention,
    );
  }
}
