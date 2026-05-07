import '../models/speed_zone.dart';
import '../models/speed_calculator.dart';

final List<SpeedZone> mbararaSpeedZones = [
  const SpeedZone(
    id: 'mile_4_roundabout',
    name: 'Mile 4 Roundabout',
    latitude: -0.6028298,
    longitude: 30.61888,
    speedLimit: 13,
    triggerRadius: 100,
    type: LocationType.roundabout,
  ),
  const SpeedZone(
    id: 'mile_4_junction',
    name: 'Mile 4 Junction',
    latitude: -0.6050219,
    longitude: 30.62268,
    speedLimit: 20,
    triggerRadius: 100,
    type: LocationType.junction,
  ),
  const SpeedZone(
    id: 'university_junction',
    name: 'University Junction',
    latitude: -0.5981669,
    longitude: 30.60997,
    speedLimit: 20,
    triggerRadius: 100,
    type: LocationType.junction,
  ),
  const SpeedZone(
    id: 'caros_garden_junction',
    name: 'Caros Garden Junction',
    latitude: -0.5938323,
    longitude: 30.60009,
    speedLimit: 20,
    triggerRadius: 100,
    type: LocationType.junction,
  ),
];