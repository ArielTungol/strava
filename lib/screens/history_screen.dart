import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/activity_provider.dart';
import '../models/activity.dart';
import '../models/route_point.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh when screen is first loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(activitiesListProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch the activities list - this will rebuild when data changes
    final activitiesAsync = ref.watch(activitiesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity History'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Manual refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(activitiesListProvider);
            },
          ),
        ],
      ),
      body: activitiesAsync.when(
        data: (activities) {
          if (activities.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No activities yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text('Start tracking your first activity!', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final activity = activities[index];
              final color = _getActivityColor(activity.type);
              final icon = _getActivityIcon(activity.type);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    _showActivityDetails(context, activity);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12)
                          ),
                          child: Icon(icon, color: color, size: 30),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(activity.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('MMM dd, yyyy • hh:mm a').format(activity.startTime),
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatDistance(activity.distance), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(_formatDuration(activity.duration), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  void _showActivityDetails(BuildContext context, Activity activity) {
    final routePoints = activity.routePoints.map((rp) => LatLng(rp.latitude, rp.longitude)).toList();
    final hasRoute = routePoints.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)
                  )
              ),
            ),
            const SizedBox(height: 20),

            // Activity name and type
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getActivityColor(activity.type).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getActivityIcon(activity.type),
                    color: _getActivityColor(activity.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        DateFormat('EEEE, MMMM dd, yyyy').format(activity.startTime),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Route preview map (if route points exist)
            if (hasRoute) ...[
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _getCenterFromRoute(routePoints),
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.strava',
                      ),
                      if (routePoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: routePoints,
                              color: _getActivityColor(activity.type).withValues(alpha: 0.8),
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          // Start marker
                          if (routePoints.isNotEmpty)
                            Marker(
                              point: routePoints.first,
                              width: 30,
                              height: 30,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.flag, color: Colors.white, size: 16),
                              ),
                            ),
                          // End marker
                          if (routePoints.length > 1)
                            Marker(
                              point: routePoints.last,
                              width: 30,
                              height: 30,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.location_on, color: Colors.white, size: 16),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Route stats
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildRouteStat('Start', _formatTimeOfDay(activity.startTime), Icons.flag, Colors.green),
                    Container(width: 1, height: 30, color: Colors.grey.shade300),
                    _buildRouteStat('End', _formatTimeOfDay(activity.endTime ?? activity.startTime), Icons.flag, Colors.red),
                    Container(width: 1, height: 30, color: Colors.grey.shade300),
                    _buildRouteStat('Points', '${routePoints.length}', Icons.route, Colors.blue),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              // No route placeholder
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'No route data available',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Stats grid
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _buildDetailStatCard(
                    'Distance',
                    activity.formattedDistance,
                    Icons.straighten,
                    _getActivityColor(activity.type),
                  ),
                  _buildDetailStatCard(
                    'Duration',
                    activity.formattedDuration,
                    Icons.timer,
                    _getActivityColor(activity.type),
                  ),
                  _buildDetailStatCard(
                    activity.type == ActivityType.cycling ? 'Avg Speed' : 'Avg Pace',
                    activity.formattedPace,
                    Icons.speed,
                    _getActivityColor(activity.type),
                  ),
                  _buildDetailStatCard(
                    'Calories',
                    activity.formattedCalories,
                    Icons.local_fire_department,
                    _getActivityColor(activity.type),
                  ),
                  if (activity.maxSpeed != null)
                    _buildDetailStatCard(
                      'Max Speed',
                      _formatSpeed(activity.maxSpeed!, activity.type),
                      Icons.flash_on,
                      _getActivityColor(activity.type),
                    ),
                  if (activity.elevationGain != null && activity.elevationGain! > 0)
                    _buildDetailStatCard(
                      'Elevation',
                      '${activity.elevationGain!.toStringAsFixed(0)}m',
                      Icons.terrain,
                      _getActivityColor(activity.type),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildDetailStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  LatLng _getCenterFromRoute(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(14.5995, 120.9842);
    if (points.length == 1) return points.first;

    // Calculate center of route
    double lat = 0, lng = 0;
    for (var point in points) {
      lat += point.latitude;
      lng += point.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  String _formatTimeOfDay(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }

  String _formatSpeed(double speed, ActivityType type) {
    if (type == ActivityType.cycling) {
      return '${(speed * 3.6).toStringAsFixed(1)} km/h';
    }
    return '${speed.toStringAsFixed(1)} m/s';
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.running: return Colors.orange;
      case ActivityType.walking: return Colors.green;
      case ActivityType.cycling: return Colors.blue;
      case ActivityType.hiking: return Colors.brown;
      case ActivityType.swimming: return Colors.lightBlue;
      case ActivityType.workout: return Colors.purple;
    }
  }

  IconData _getActivityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.running: return Icons.directions_run;
      case ActivityType.walking: return Icons.directions_walk;
      case ActivityType.cycling: return Icons.directions_bike;
      case ActivityType.hiking: return Icons.hiking;
      case ActivityType.swimming: return Icons.pool;
      case ActivityType.workout: return Icons.fitness_center;
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _formatDuration(double seconds) {
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    int secs = (seconds % 60).floor();

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }
}