import 'speed_calculator.dart';

class SpeedZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int speedLimit;
  final int triggerRadius;
  final LocationType type;

  const SpeedZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.speedLimit,
    this.triggerRadius = 100,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'speedLimit': speedLimit,
        'triggerRadius': triggerRadius,
        'type': type.index,
      };

  factory SpeedZone.fromJson(Map<String, dynamic> json) => SpeedZone(
        id: json['id'] as String,
        name: json['name'] as String,
        latitude: json['latitude'] as double,
        longitude: json['longitude'] as double,
        speedLimit: json['speedLimit'] as int,
        triggerRadius: json['triggerRadius'] as int? ?? 100,
        type: LocationType.values[json['type'] as int],
      );
}