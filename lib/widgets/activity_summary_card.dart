import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';

class ActivitySummaryCard extends ConsumerWidget {
  final double distance;
  final double duration;
  final double speed;
  final ActivityType type;

  const ActivitySummaryCard({
    super.key,
    required this.distance,
    required this.duration,
    required this.speed,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _getActivityColor(type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_getActivityIcon(type), color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Text(_getActivityName(type), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat('Distance', _formatDistance(distance)),
              _buildStat('Duration', _formatDuration(duration)),
              _buildStat('Speed', _formatSpeed(speed, type)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _formatDuration(double seconds) {
    int minutes = (seconds / 60).floor();
    int remainingSeconds = (seconds % 60).floor();
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _formatSpeed(double speed, ActivityType type) {
    if (type == ActivityType.cycling) {
      double speedKmh = speed * 3.6;
      return '${speedKmh.toStringAsFixed(1)} km/h';
    } else {
      if (speed <= 0) return '0:00';
      double pace = 1000 / (speed * 60);
      int minutes = pace.floor();
      int seconds = ((pace - minutes) * 60).floor();
      return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
    }
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.running:
        return Colors.orange;
      case ActivityType.walking:
        return Colors.green;
      case ActivityType.cycling:
        return Colors.blue;
      case ActivityType.hiking:
        return Colors.brown;
      case ActivityType.swimming:
        return Colors.lightBlue;
      case ActivityType.workout:
        return Colors.purple;
    }
  }

  IconData _getActivityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.cycling:
        return Icons.directions_bike;
      case ActivityType.hiking:
        return Icons.hiking;
      case ActivityType.swimming:
        return Icons.pool;
      case ActivityType.workout:
        return Icons.fitness_center;
    }
  }

  String _getActivityName(ActivityType type) {
    switch (type) {
      case ActivityType.running:
        return 'Running';
      case ActivityType.walking:
        return 'Walking';
      case ActivityType.cycling:
        return 'Cycling';
      case ActivityType.hiking:
        return 'Hiking';
      case ActivityType.swimming:
        return 'Swimming';
      case ActivityType.workout:
        return 'Workout';
    }
  }
}