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
        // By name, not index. `LocationType` has already grown from six values
        // to eight, and index-based storage only survived that because the new
        // members happened to be appended.
        'type': type.name,
      };

  factory SpeedZone.fromJson(Map<String, dynamic> json) => SpeedZone(
        id: json['id'] as String,
        name: json['name'] as String,
        latitude: json['latitude'] as double,
        longitude: json['longitude'] as double,
        speedLimit: json['speedLimit'] as int,
        triggerRadius: json['triggerRadius'] as int? ?? 100,
        type: _locationTypeFrom(json['type']),
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

  /// Zones are collected into a `Set` while matching. Without value equality
  /// that set iterates in identity-hash order, which made the *same*
  /// coordinate resolve to different speed limits between runs.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SpeedZone && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SpeedZone($id, ${speedLimit}kph, r=${triggerRadius}m)';
}