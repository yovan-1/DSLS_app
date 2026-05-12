import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide DayPeriod;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../models/speed_calculator.dart';
import '../models/trip_data.dart';
import '../services/trip_service.dart';
import '../widgets/score_card.dart';
import '../widgets/trip_list_item.dart';
import '../widgets/stats_row.dart';
import '../widgets/trend_graph.dart';
import '../widgets/behavior_summary.dart';
import '../widgets/driving_graph.dart';
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
                  : RefreshIndicator(
                    onRefresh: () async {
                      setState(() {});
                    },
                    child: SingleChildScrollView(
                      physics: AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_selectedLocation != null || _startDate != null)
                            _buildActiveFilters(),
                          ScoreCard(score: score),
                          SizedBox(height: 20),
                          _buildSummaryCards(tripService),
                          SizedBox(height: 20),
                          StatsRow(service: tripService),
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
                            (trip) => TripListItem(
                              trip: trip,
                              service: tripService,
                              onDelete: (id) => tripService.deleteTrip(id),
                            ),
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
                          DrivingGraph(),
                          SizedBox(height: 15),
                          BehaviorSummary(tripService: tripService),
                          SizedBox(height: 20),
                          Text(
                            "Risk Trends (Last 7 Days)",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 10),
                          TrendGraph(trips: filteredTrips.take(7).toList()),
                        ],
                      ),
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

  void _showClearDialog(BuildContext context, TripService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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

  String _formatDate(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
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
