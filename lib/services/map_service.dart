import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class MapService {
  final MapController _mapController = MapController();

  MapController get mapController => _mapController;

  static const double defaultZoom = 15.0;
  static const double defaultLat = 0.3476;
  static const double defaultLon = 32.5825;

  LatLng get defaultLocation => LatLng(defaultLat, defaultLon);

  Future<LatLng> getCurrentLocation() async {
    try {
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        return defaultLocation;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('[MapService] Error getting location: $e');
      return defaultLocation;
    }
  }

  Future<bool> _checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  void moveToLocation(LatLng location, {double? zoom}) {
    try {
      _mapController.move(location, zoom ?? defaultZoom);
    } catch (e) {
      debugPrint('[MapService] Error moving map: $e');
    }
  }

  void moveToPosition(double lat, double lon, {double? zoom}) {
    moveToLocation(LatLng(lat, lon), zoom: zoom);
  }

  List<LatLng> createRouteFromPoints(List<Position> positions) {
    return positions.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  List<LatLng> estimateTripRoute(LatLng start, LatLng end) {
    const points = 20;
    final route = <LatLng>[];

    for (int i = 0; i <= points; i++) {
      final lat = start.latitude + (end.latitude - start.latitude) * i / points;
      final lon = start.longitude + (end.longitude - start.longitude) * i / points;
      route.add(LatLng(lat, lon));
    }

    return route;
  }

  double calculateDistance(LatLng start, LatLng end) {
    const distance = Distance();
    return distance.as(LengthUnit.Kilometer, start, end);
  }

  void dispose() {
    _mapController.dispose();
  }
}

class MapMarker {
  final LatLng position;
  final String? title;
  final String? description;
  final int? color;

  const MapMarker({
    required this.position,
    this.title,
    this.description,
    this.color,
  });
}

class MapOptions {
  final LatLng initialPosition;
  final double initialZoom;
  final String mapTileUrl;

  const MapOptions({
    required this.initialPosition,
    this.initialZoom = 15.0,
    this.mapTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  });

  static const MapOptions defaultOptions = MapOptions(
    initialPosition: LatLng(0.3476, 32.5825),
    initialZoom: 15.0,
  );
}