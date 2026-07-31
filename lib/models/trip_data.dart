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
    // By name, not index. LocationType has already grown from six values to
    // eight and only survived index-based storage because the new members
    // happened to be appended.
    'location': location.name,
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
    location: _locationTypeFrom(json['location']),
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

  /// Accepts both the current name form and the legacy index form.
  static LocationType _locationTypeFrom(Object? raw) {
    if (raw is int) {
      return raw >= 0 && raw < LocationType.values.length
          ? LocationType.values[raw]
          : LocationType.urban;
    }
    return LocationType.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => LocationType.urban,
    );
  }
}

/// One alert *episode* — a continuous stretch where the driver was over the
/// recommended speed — rather than a single sample.
///
/// [time] opens the episode, [endTime] closes it and [peakSpeed] is the worst
/// speed reached while it was open. Before this, one over-limit stretch
/// produced an alert per sample, so a half-hour of speeding logged thousands of
/// them and any statistic derived from the count described the recording rate
/// rather than the driving.
class SpeedAlert {
  final String id;
  final DateTime time;

  /// Null while the episode is still open.
  final DateTime? endTime;

  /// The speed at the moment the episode opened.
  final int speed;

  /// The worst speed reached during the episode. Defaults to [speed] for a
  /// freshly opened episode and for records migrated from the old format,
  /// where only the opening sample was kept.
  final int peakSpeed;

  final int recommendedSpeed;
  final AlertType type;

  SpeedAlert({
    required this.id,
    required this.time,
    this.endTime,
    required this.speed,
    int? peakSpeed,
    required this.recommendedSpeed,
    required this.type,
  }) : peakSpeed = peakSpeed ?? speed;

  Duration? get duration => endTime?.difference(time);

  bool get isOpen => endTime == null;

  SpeedAlert copyWith({DateTime? endTime, int? peakSpeed}) => SpeedAlert(
        id: id,
        time: time,
        endTime: endTime ?? this.endTime,
        speed: speed,
        peakSpeed: peakSpeed ?? this.peakSpeed,
        recommendedSpeed: recommendedSpeed,
        type: type,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'speed': speed,
    'peakSpeed': peakSpeed,
    'recommendedSpeed': recommendedSpeed,
    // By name, not index. AlertType currently has four values of which only
    // one is ever constructed; reordering or pruning it must not silently
    // rewrite stored history.
    'type': type.name,
  };

  factory SpeedAlert.fromJson(Map<String, dynamic> json) => SpeedAlert(
    id: json['id'],
    time: DateTime.parse(json['time']),
    endTime:
        json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    speed: json['speed'],
    peakSpeed: json['peakSpeed'],
    recommendedSpeed: json['recommendedSpeed'],
    type: _alertTypeFrom(json['type']),
  );

  /// Accepts both the current name form and the legacy index form.
  static AlertType _alertTypeFrom(Object? raw) {
    if (raw is int) {
      return raw >= 0 && raw < AlertType.values.length
          ? AlertType.values[raw]
          : AlertType.overSpeed;
    }
    return AlertType.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => AlertType.overSpeed,
    );
  }
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

  /// How many recent trips the score reflects.
  static const int windowSize = 10;

  /// Scores the most recent [windowSize] trips, averaging per trip.
  ///
  /// This used to sum `overSpeedCount` and `alerts.length` across *every trip
  /// ever* and subtract the clamped total. Because the penalties clamped at 50
  /// and 40, roughly ten lifetime over-speed episodes pinned the score at its
  /// floor permanently: it decayed monotonically and no amount of good driving
  /// afterwards could move it, which makes it useless as feedback.
  ///
  /// Now each trip is scored on its own and the window is averaged, so
  /// improving actually shows up.
  static DrivingScore calculate(List<TripData> trips) {
    if (trips.isEmpty) {
      return const DrivingScore(
        overall: 0,
        speedCompliance: 0,
        smoothness: 0,
        attention: 0,
      );
    }

    // Most recent first, then take the window.
    final ordered = List<TripData>.from(trips)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final window = ordered.take(windowSize).toList();

    var complianceSum = 0;
    var smoothnessSum = 0;
    var attentionSum = 0;

    for (final trip in window) {
      complianceSum += forTrip(trip).speedCompliance;
      smoothnessSum += forTrip(trip).smoothness;
      attentionSum += forTrip(trip).attention;
    }

    final count = window.length;
    return _compose(
      speedCompliance: (complianceSum / count).round(),
      smoothness: (smoothnessSum / count).round(),
      attention: (attentionSum / count).round(),
    );
  }

  /// Scores a single trip, so one bad drive stays one bad drive.
  static DrivingScore forTrip(TripData trip) {
    final speedCompliance = 100 - (trip.overSpeedCount * 5).clamp(0, 60);
    final smoothness = 100 - (trip.alerts.length * 3).clamp(0, 50);
    final attention =
        (trip.duration != null && trip.duration!.inHours > 2) ? 70 : 90;

    return _compose(
      speedCompliance: speedCompliance,
      smoothness: smoothness,
      attention: attention,
    );
  }

  static DrivingScore _compose({
    required int speedCompliance,
    required int smoothness,
    required int attention,
  }) {
    final overall =
        ((speedCompliance * 0.4) + (smoothness * 0.4) + (attention * 0.2))
            .round();

    return DrivingScore(
      overall: overall.clamp(0, 100),
      speedCompliance: speedCompliance.clamp(0, 100),
      smoothness: smoothness.clamp(0, 100),
      attention: attention.clamp(0, 100),
    );
  }
}
