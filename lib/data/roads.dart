import '../models/road_segment.dart';
import '../models/speed_calculator.dart';

final List<RoadSegment> mbararaRoads = [
  RoadSegment(
    id: 'mbarara_kasese_road',
    name: 'Mbarara Kasese Road',
    waypoints: const [
      MapPoint(latitude: -0.6118676, longitude: 30.63680),
      MapPoint(latitude: -0.5898870, longitude: 30.58509),
    ],
    speedLimit: 56,
    widthMeters: 20,
    type: LocationType.highway,
  ),
  RoadSegment(
    id: 'mbarara_northern_bypass',
    name: 'Mbarara Northern Bypass',
    waypoints: const [
      MapPoint(latitude: -0.5833907, longitude: 30.67969),
      MapPoint(latitude: -0.6300887, longitude: 30.60031),
    ],
    speedLimit: 80,
    widthMeters: 20,
    type: LocationType.highway,
  ),
];