import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide DayPeriod;
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/speed_calculator.dart';
import '../models/trip_data.dart';
import '../services/trip_service.dart';
import 'trip_details_screen.dart';

class HistoryScreen extends StatefulWidget {
  final Function(int)? onBack;

  const HistoryScreen({super.key, this.onBack});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _selectedLocation;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    return Consumer<TripService>(
      builder: (context, tripService, child) {
        final allTrips = tripService.recentTrips;
        final filteredTrips = _filterTrips(allTrips);
        final score = tripService.drivingScore;

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => widget.onBack?.call(0),
            ),
            title: Text("Trip History", style: TextStyle(color: Colors.black)),
            centerTitle: true,
            actions: [
              if (filteredTrips.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.filter_list, color: Colors.blue),
                  onPressed: () => _showFilterDialog(context),
                ),
              if (filteredTrips.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.download, color: Colors.green),
                  onPressed: () => _exportTrips(context, filteredTrips),
                ),
              if (allTrips.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _showClearDialog(context, tripService),
                ),
            ],
          ),
          body:
              filteredTrips.isEmpty && allTrips.isEmpty
                  ? _buildEmptyState()
                  : SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedLocation != null || _startDate != null)
                          _buildActiveFilters(),
                        _buildScoreCard(score),
                        SizedBox(height: 20),
                        _buildSummaryCards(tripService),
                        SizedBox(height: 20),
                        _buildStatsRow(tripService),
                        SizedBox(height: 20),
                        Text(
                          filteredTrips.length != allTrips.length
                              ? "Filtered Trips (${filteredTrips.length})"
                              : "Recent Trips",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 10),
                        ...filteredTrips.map(
                          (trip) => _buildTripCard(context, trip, tripService),
                        ),
                        SizedBox(height: 20),
                        Text(
                          "Current Session Data",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 10),
                        _buildDrivingDataGraph(tripService),
                        SizedBox(height: 15),
                        _buildBehaviorSummary(tripService),
                        SizedBox(height: 20),
                        Text(
                          "Risk Trends (Last 7 Days)",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 10),
                        _buildTrendGraph(filteredTrips),
                      ],
                    ),
                  ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car, size: 80, color: Colors.grey.shade400),
          SizedBox(height: 20),
          Text(
            "No trips yet",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 10),
          Text(
            "Start a trip from the Speed screen",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(DrivingScore score) {
    Color scoreColor;
    if (score.overall >= 80) {
      scoreColor = Colors.green;
    } else if (score.overall >= 60) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scoreColor, scoreColor.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                score.grade,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
              ),
            ),
          ),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Driving Score",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  score.description,
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    _buildMiniStat("Speed", "${score.speedCompliance}%"),
                    SizedBox(width: 15),
                    _buildMiniStat("Smooth", "${score.smoothness}%"),
                    SizedBox(width: 15),
                    _buildMiniStat("Focus", "${score.attention}%"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _buildStatsRow(TripService service) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            "Total Trips",
            "${service.totalTrips}",
            Icons.directions_car,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            "Total Distance",
            "${service.totalDistance} km",
            Icons.route,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            "Avg Speed",
            "${service.averageSpeed.round()} km/h",
            Icons.speed,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.blue),
          SizedBox(height: 5),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTripCard(
    BuildContext context,
    TripData trip,
    TripService service,
  ) {
    final locationLabel = SpeedCalculator.getLocationLabel(trip.location);
    final riskColor =
        trip.overSpeedCount > 5
            ? Colors.red
            : (trip.overSpeedCount > 2 ? Colors.orange : Colors.green);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
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
                    Icon(Icons.directions_car, color: Colors.blue),
                    SizedBox(width: 10),
                    Text(
                      locationLabel,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  _formatDate(trip.startTime),
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTripStat("Duration", trip.formattedDuration),
                _buildTripStat("Max Speed", "${trip.maxSpeed} km/h"),
                _buildTripStat(
                  "Over Speed",
                  "${trip.overSpeedCount}x",
                  color: riskColor,
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Recommended: ${trip.recommendedSpeed} km/h",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  children: [
                    Text(
                      "Tap for details",
                      style: TextStyle(fontSize: 10, color: Colors.blue.shade300),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _confirmDelete(context, trip.id, service),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red.shade300,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String tripId, TripService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Trip"),
        content: Text("Are you sure you want to delete this trip?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              service.deleteTrip(tripId);
              Navigator.pop(context);
            },
            child: Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildTripStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTrendGraph(List<TripData> trips) {
    return Container(
      height: 120,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) {
          final trip = index < trips.length ? trips[index] : null;
          final height =
              trip != null
                  ? (100 - trip.overSpeedCount * 10).clamp(20, 100).toDouble()
                  : 20.0;
          final color =
              (trip?.overSpeedCount ?? 0) > 3 ? Colors.red : Colors.green;

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 30,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(height: 5),
              Text(
                ["M", "T", "W", "T", "F", "S", "S"][index],
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDrivingDataGraph(TripService tripService) {
    final records = tripService.drivingRecords;

    if (records.isEmpty) {
      return Container(
        height: 200,
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 50, color: Colors.grey.shade400),
              SizedBox(height: 10),
              Text(
                "No data available",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              Text(
                "Start driving to see real-time data",
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final speedSpots = <FlSpot>[];
    final riskSpots = <FlSpot>[];

    for (int i = 0; i < records.length; i++) {
      speedSpots.add(FlSpot(i.toDouble(), records[i].speed.toDouble()));

      int riskValue;
      switch (records[i].riskLevel) {
        case 'HIGH':
          riskValue = 100;
          break;
        case 'MEDIUM':
          riskValue = 50;
          break;
        default:
          riskValue = 0;
      }
      riskSpots.add(FlSpot(i.toDouble(), riskValue.toDouble()));
    }

    return Container(
      height: 220,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Speed vs Time",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          SizedBox(height: 10),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 30,
                  getDrawingHorizontalLine:
                      (value) =>
                          FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 30,
                      getTitlesWidget:
                          (value, meta) => Text(
                            '${value.toInt()}',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: (records.length / 5).ceilToDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= records.length) return SizedBox();
                        final seconds = value.toInt();
                        return Text(
                          '${seconds}s',
                          style: TextStyle(fontSize: 9, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (records.length - 1).toDouble().clamp(0, double.infinity),
                minY: 0,
                maxY: 150,
                lineBarsData: [
                  LineChartBarData(
                    spots: speedSpots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10),
          Text(
            "Risk Level",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          SizedBox(height: 10),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine:
                      (value) =>
                          FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 25,
                      getTitlesWidget: (value, meta) {
                        String label;
                        if (value >= 75) {
                          label = 'HIGH';
                        } else if (value >= 25) {
                          label = 'MED';
                        } else {
                          label = 'LOW';
                        }
                        return Text(
                          label,
                          style: TextStyle(fontSize: 9, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (records.length - 1).toDouble().clamp(0, double.infinity),
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: riskSpots,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orange.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 5),
          Text(
            "Records: ${records.length}",
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorSummary(TripService tripService) {
    final safe = tripService.safeDrivingPercent;
    final moderate = tripService.moderateDrivingPercent;
    final risky = tripService.riskyDrivingPercent;

    if (tripService.drivingRecords.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Driving Behavior Analysis",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _buildBehaviorCard(
                  "Safe",
                  "$safe%",
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _buildBehaviorCard(
                  "Moderate",
                  "$moderate%",
                  Colors.orange,
                  Icons.warning,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _buildBehaviorCard(
                  "Risky",
                  "$risky%",
                  Colors.red,
                  Icons.dangerous,
                ),
              ),
            ],
          ),
          SizedBox(height: 15),
          LinearProgressIndicator(
            value: safe / 100,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Safe", style: TextStyle(fontSize: 10, color: Colors.green)),
              Text(
                "Moderate",
                style: TextStyle(fontSize: 10, color: Colors.orange),
              ),
              Text("Risky", style: TextStyle(fontSize: 10, color: Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBehaviorCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _showClearDialog(BuildContext context, TripService service) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text("Clear History"),
            content: Text("Are you sure you want to delete all trip history?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  service.clearHistory();
                  Navigator.pop(context);
                },
                child: Text("Clear", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  List<TripData> _filterTrips(List<TripData> trips) {
    return trips.where((trip) {
      if (_selectedLocation != null && trip.location.name != _selectedLocation) {
        return false;
      }
      if (_startDate != null && trip.startTime.isBefore(_startDate!)) {
        return false;
      }
      if (_endDate != null && trip.startTime.isAfter(_endDate!)) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildActiveFilters() {
    return Container(
      margin: EdgeInsets.only(bottom: 15),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 16, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _getFilterLabel(),
              style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _selectedLocation = null;
              _startDate = null;
              _endDate = null;
            }),
            child: Icon(Icons.close, size: 16, color: Colors.blue),
          ),
        ],
      ),
    );
  }

  String _getFilterLabel() {
    final parts = <String>[];
    if (_selectedLocation != null) {
      parts.add('Location: $_selectedLocation');
    }
    if (_startDate != null) {
      parts.add('From: ${_formatDate(_startDate!)}');
    }
    if (_endDate != null) {
      parts.add('To: ${_formatDate(_endDate!)}');
    }
    return parts.join(', ');
  }

  void _showFilterDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Filter Trips", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Text("Location", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: LocationType.values.map((loc) {
                final isSelected = _selectedLocation == loc.name;
                return ChoiceChip(
                  label: Text(SpeedCalculator.getLocationLabel(loc)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedLocation = selected ? loc.name : null;
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            SizedBox(height: 20),
            Text("Date Range", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        if (!context.mounted) return;
                        setState(() {
                          _startDate = date;
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: Text(_startDate != null ? _formatDate(_startDate!) : "Start Date"),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        if (!context.mounted) return;
                        setState(() {
                          _endDate = date;
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: Text(_endDate != null ? _formatDate(_endDate!) : "End Date"),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _selectedLocation = null;
                    _startDate = null;
                    _endDate = null;
                  });
                  Navigator.pop(context);
                },
                child: Text("Clear Filters"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportTrips(BuildContext context, List<TripData> trips) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Export Trip History"),
        content: Text("Choose export format:"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'json'),
            child: Text("JSON"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'csv'),
            child: Text("CSV"),
          ),
        ],
      ),
    );

    if (choice == null) return;

    String content;
    String filename;
    if (choice == 'json') {
      content = jsonEncode(trips.map((t) => t.toJson()).toList());
      filename = 'trip_history_${DateTime.now().millisecondsSinceEpoch}.json';
    } else {
      final buffer = StringBuffer();
      buffer.writeln('Date,Location,Duration (min),Max Speed,Avg Speed,Over Speed Count,Recommended Speed');
      for (final trip in trips) {
        buffer.writeln(
          '${_formatDate(trip.startTime)},'
          '${SpeedCalculator.getLocationLabel(trip.location)},'
          '${trip.duration?.inMinutes ?? 0},'
          '${trip.maxSpeed},'
          '${trip.avgSpeed},'
          '${trip.overSpeedCount},'
          '${trip.recommendedSpeed}',
        );
      }
      content = buffer.toString();
      filename = 'trip_history_${DateTime.now().millisecondsSinceEpoch}.csv';
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(content);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Exported to $filename")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Export failed: $e")),
        );
      }
    }
  }

  Widget _buildSummaryCards(TripService service) {
    final weekly = service.weeklySummary;
    final monthly = service.monthlySummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Weekly Summary",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                "${weekly['trips']}",
                "Trips",
                Icons.directions_car,
                Colors.blue,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                "${weekly['distance']}",
                "km",
                Icons.route,
                Colors.green,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                "${weekly['overspeed']}",
                "Over Speed",
                Icons.warning,
                (weekly['overspeed'] as int) > 5 ? Colors.red : Colors.orange,
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        Text(
          "Monthly Summary",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                "${monthly['trips']}",
                "Trips",
                Icons.directions_car,
                Colors.blue,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                "${monthly['distance']}",
                "km",
                Icons.route,
                Colors.green,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCard(
                "${monthly['overspeed']}",
                "Over Speed",
                Icons.warning,
                (monthly['overspeed'] as int) > 10 ? Colors.red : Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 5)],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}
