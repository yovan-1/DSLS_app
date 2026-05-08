import '../models/speed_zone.dart';
import '../models/speed_calculator.dart';

final List<SpeedZone> mbararaSpeedZones = [
  const SpeedZone(
    id: 'parking',
    name: 'MUST Parking Space',
    latitude: -0.5957975,
    longitude: 30.60024,
    speedLimit: 20,
    triggerRadius: 10,
    type: LocationType.schoolZone,
  ),
  const SpeedZone(
    id: 'main_gate',
    name: 'Mbarara University',
    latitude: -0.5945678,
    longitude: 30.59981,
    speedLimit: 30,
    triggerRadius: 30,
    type: LocationType.schoolZone,
  ),
  const SpeedZone(
    id: 'roundabout',
    name: 'Mile 4 Roundabout',
    latitude: -0.6028074,
    longitude: 30.61884,
    speedLimit: 35,
    triggerRadius: 30,
    type: LocationType.roundabout,
  ),
  const SpeedZone(
    id: 'turn',
    name: 'Ibanda Junction',
    latitude: -0.5981443,
    longitude: 30.60997,
    speedLimit: 40,
    triggerRadius: 30,
    type: LocationType.junction,
  ),
  const SpeedZone(
    id: 'ruharo_junction',
    name: 'Ruharo Junction',
    latitude: -0.6120,
    longitude: 30.6350,
    speedLimit: 30,
    triggerRadius: 80,
    type: LocationType.junction,
  ),
];