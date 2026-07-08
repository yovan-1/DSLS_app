import 'package:flutter/material.dart' hide DayPeriod;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/route_service.dart';
import '../models/speed_calculator.dart';

class RouteScreen extends StatelessWidget {
  const RouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (context, routeService, child) {
        final routes = routeService.getRecommendations();

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              "Route Recommendations",
              style: TextStyle(color: Colors.black),
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMapSection(),
                SizedBox(height: 20),
                _buildCurrentConditions(routeService),
                SizedBox(height: 20),
                Text(
                  "Recommended Routes",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                ...routes.asMap().entries.map(
                  (entry) => _buildRouteCard(context, entry.value, entry.key == 0),
                ),
                SizedBox(height: 20),
                _buildRouteTips(routeService),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapSection() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(0.3476, 32.5825),
          initialZoom: 13.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.dsls_app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(0.3476, 32.5825),
                width: 40,
                height: 40,
                child: Icon(
                  Icons.location_on,
                  color: Colors.blue,
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentConditions(RouteService service) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Current Conditions",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildConditionItem(
                Icons.location_on,
                SpeedCalculator.getLocationLabel(service.currentLocation),
              ),
              _buildConditionItem(
                SpeedCalculator.getWeatherIcon(service.weather),
                SpeedCalculator.getWeatherLabel(service.weather),
              ),
              _buildConditionItem(
                Icons.access_time,
                SpeedCalculator.getTimeLabel(service.timeOfDay).split(' ')[0],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionItem(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildRouteCard(BuildContext context, RouteRecommendation route, bool isRecommended) {
    final color = _getSafetyColor(route.safetyScore);
    final typeIcon = _getRouteTypeIcon(route.type);

    return Container(
      margin: EdgeInsets.only(bottom: 15),
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: isRecommended ? Border.all(color: Colors.blue, width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (isRecommended)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "BEST",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (isRecommended) SizedBox(width: 8),
                  Icon(typeIcon, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    route.name,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${route.safetyScore}%",
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            route.description,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.straighten, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text("${route.distance} km", style: TextStyle(fontSize: 12)),
                  SizedBox(width: 15),
                  Icon(Icons.timer, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text(
                    "${route.estimatedTime} min",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => _openMapsNavigation(context, route),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        "Navigate",
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children:
                route.benefits
                    .map(
                      (b) => Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          b,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _openMapsNavigation(BuildContext context, RouteRecommendation route) async {
    final center = LatLng(0.3476, 32.5825);
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${center.latitude},${center.longitude}&travelmode=driving',
    );

    final appleMapsUrl = Uri.parse(
      'https://maps.apple.com/?daddr=${center.latitude},${center.longitude}&dirflg=d',
    );

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Unable to open maps. You can navigate to: ${route.name}"),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error opening maps: $e")),
        );
      }
    }
  }

  Widget _buildRouteTips(RouteService service) {
    List<String> tips = [];

    if (service.weather == WeatherCondition.rain ||
        service.weather == WeatherCondition.heavyRain) {
      tips.add("Reduced speed due to wet roads");
    }
    if (service.weather == WeatherCondition.fog) {
      tips.add("Use low beam headlights in fog");
    }
    if (service.timeOfDay == DayPeriod.night) {
      tips.add("Drive with extra caution at night");
    }
    if (service.currentLocation == LocationType.schoolZone) {
      tips.add("Watch for children during school hours");
    }
    if (service.currentLocation == LocationType.constructionZone) {
      tips.add("Follow reduced speed in construction areas");
    }

    if (tips.isEmpty) {
      tips.add("Conditions are favorable for driving");
    }

    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                "Safety Tips",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 10),
          ...tips.map(
            (tip) => Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(Icons.arrow_right, size: 16, color: Colors.orange),
                  Expanded(child: Text(tip, style: TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSafetyColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  IconData _getRouteTypeIcon(RouteType type) {
    switch (type) {
      case RouteType.fastest:
        return Icons.speed;
      case RouteType.safest:
        return Icons.shield;
      case RouteType.scenic:
        return Icons.landscape;
      case RouteType.alternative:
        return Icons.route;
    }
  }
}
