import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/activity_provider.dart';
import '../models/activity.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activitiesListProvider);
    final statsAsync = ref.watch(activityStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: activitiesAsync.when(
        data: (activities) {
          if (activities.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics_outlined, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No stats available', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text('Complete activities to see your stats', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                ],
              ),
            );
          }

          return statsAsync.when(
            data: (stats) => _buildStatsContent(activities, stats),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildStatsContent(List<Activity> activities, Map<String, dynamic> stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildStatCard('Total Activities', stats['totalActivities'].toString(), Icons.fitness_center, Colors.blue),
              _buildStatCard('Total Distance', _formatDistance(stats['totalDistance']), Icons.straighten, Colors.green),
              _buildStatCard('Total Time', _formatDuration(stats['totalDuration']), Icons.timer, Colors.orange),
              _buildStatCard('Total Elevation', '${(stats['totalElevation']).toStringAsFixed(0)}m', Icons.terrain, Colors.purple),
            ],
          ),

          const SizedBox(height: 24),

          const Text('Averages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(_formatDistance(stats['averageDistance']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 4),
                    Text('Avg Distance', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
                Container(height: 30, width: 1, color: Colors.grey.shade300),
                Column(
                  children: [
                    Text(_formatDuration(stats['averageDuration']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 4),
                    Text('Avg Duration', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text('Recent Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          ...activities.take(5).map((activity) => _buildRecentActivityItem(activity)),

          const SizedBox(height: 16),

          const Text('Activity Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          _buildActivityBreakdown(activities),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildRecentActivityItem(Activity activity) {
    final color = _getActivityColor(activity.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(_getActivityIcon(activity.type), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activity.name, style: const TextStyle(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(DateFormat('MMM dd, yyyy').format(activity.startTime), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatDistance(activity.distance), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_formatDuration(activity.duration), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityBreakdown(List<Activity> activities) {
    Map<ActivityType, int> counts = {
      ActivityType.running: 0,
      ActivityType.walking: 0,
      ActivityType.cycling: 0,
      ActivityType.hiking: 0,
      ActivityType.swimming: 0,
      ActivityType.workout: 0,
    };

    Map<ActivityType, double> distances = {
      ActivityType.running: 0,
      ActivityType.walking: 0,
      ActivityType.cycling: 0,
      ActivityType.hiking: 0,
      ActivityType.swimming: 0,
      ActivityType.workout: 0,
    };

    for (var activity in activities) {
      counts[activity.type] = (counts[activity.type] ?? 0) + 1;
      distances[activity.type] = (distances[activity.type] ?? 0) + activity.distance;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildBreakdownRow('Running', counts[ActivityType.running]!, distances[ActivityType.running]!, Colors.orange, Icons.directions_run),
          const SizedBox(height: 12),
          _buildBreakdownRow('Walking', counts[ActivityType.walking]!, distances[ActivityType.walking]!, Colors.green, Icons.directions_walk),
          const SizedBox(height: 12),
          _buildBreakdownRow('Cycling', counts[ActivityType.cycling]!, distances[ActivityType.cycling]!, Colors.blue, Icons.directions_bike),
          const SizedBox(height: 12),
          _buildBreakdownRow('Hiking', counts[ActivityType.hiking]!, distances[ActivityType.hiking]!, Colors.brown, Icons.hiking),
          const SizedBox(height: 12),
          _buildBreakdownRow('Swimming', counts[ActivityType.swimming]!, distances[ActivityType.swimming]!, Colors.lightBlue, Icons.pool),
          const SizedBox(height: 12),
          _buildBreakdownRow('Workout', counts[ActivityType.workout]!, distances[ActivityType.workout]!, Colors.purple, Icons.fitness_center),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, int count, double distance, Color color, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
        Expanded(child: Text('$count activities', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
        Text(_formatDistance(distance), style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
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
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    if (seconds < 3600) {
      int minutes = (seconds / 60).floor();
      return '${minutes}m';
    }
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }
}