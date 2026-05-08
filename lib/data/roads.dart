import '../models/road_segment.dart';
import '../models/speed_calculator.dart';

final List<RoadSegment> mbararaRoads = [
  RoadSegment(
    id: 'northern_bypass',
    name: 'Mbarara Northern Bypass',
    waypoints: const [
      MapPoint(latitude: -0.5814, longitude: 30.6583),
      MapPoint(latitude: -0.5900, longitude: 30.6800),
    ],
    speedLimit: 80,
    widthMeters: 25,
    type: LocationType.highway,
  ),
  RoadSegment(
    id: 'kampala_road',
    name: 'Kampala Road',
    waypoints: const [
      MapPoint(latitude: -0.6100, longitude: 30.6600),
      MapPoint(latitude: -0.5800, longitude: 30.6700),
    ],
    speedLimit: 50,
    widthMeters: 20,
    type: LocationType.urban,
  ),
];