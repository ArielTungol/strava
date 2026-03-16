import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import 'route_point.dart';

part 'activity.g.dart';

@HiveType(typeId: 0)
enum ActivityType {
  @HiveField(0)
  running,
  @HiveField(1)
  walking,
  @HiveField(2)
  cycling,
  @HiveField(3)
  hiking,
  @HiveField(4)
  swimming,
  @HiveField(5)
  workout
}

@HiveType(typeId: 1)
class Activity extends Equatable {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final DateTime startTime;

  @HiveField(4)
  final DateTime? endTime;

  @HiveField(5)
  final double distance;

  @HiveField(6)
  final double duration;

  @HiveField(7)
  final double averageSpeed;

  @HiveField(8)
  final double? maxSpeed;

  @HiveField(9)
  final double? elevationGain;

  @HiveField(10)
  final int caloriesBurned;

  @HiveField(11)
  final List<RoutePoint> routePoints;

  @HiveField(12)
  final ActivityType type;

  @HiveField(13)
  final double? averageHeartRate;

  @HiveField(14)
  final double? maxHeartRate;

  @HiveField(15)
  final String? photoUrl;

  @HiveField(16)
  final int kudos;

  @HiveField(17)
  final List<String> comments;

  @HiveField(18)
  final bool isPrivate;

  @HiveField(19)
  final String? gearId;

  @HiveField(20)
  final int achievementCount;

  const Activity({
    required this.id,
    required this.name,
    this.description = '',
    required this.startTime,
    this.endTime,
    required this.distance,
    required this.duration,
    required this.averageSpeed,
    this.maxSpeed,
    this.elevationGain,
    this.caloriesBurned = 0,
    required this.routePoints,
    required this.type,
    this.averageHeartRate,
    this.maxHeartRate,
    this.photoUrl,
    this.kudos = 0,
    this.comments = const [],
    this.isPrivate = false,
    this.gearId,
    this.achievementCount = 0,
  });

  bool get isCompleted => endTime != null;

  String get formattedDistance {
    if (distance < 1000) return '${distance.toStringAsFixed(0)}m';
    return '${(distance / 1000).toStringAsFixed(2)}km';
  }

  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String get formattedPace {
    if (type == ActivityType.cycling) {
      final speedKmh = averageSpeed * 3.6;
      return '${speedKmh.toStringAsFixed(1)} km/h';
    } else {
      if (averageSpeed <= 0) return '--:--';
      final pace = 1000 / (averageSpeed * 60);
      final minutes = pace.floor();
      final seconds = ((pace - minutes) * 60).floor();
      return '$minutes:${seconds.toString().padLeft(2, '0')} /km';
    }
  }

  String get formattedCalories => '$caloriesBurned kcal';

  String get formattedDate => DateFormat('MMM d, yyyy').format(startTime);

  String get formattedTime => DateFormat('h:mm a').format(startTime);

  Activity copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    double? distance,
    double? duration,
    double? averageSpeed,
    double? maxSpeed,
    double? elevationGain,
    int? caloriesBurned,
    List<RoutePoint>? routePoints,
    ActivityType? type,
    double? averageHeartRate,
    double? maxHeartRate,
    String? photoUrl,
    int? kudos,
    List<String>? comments,
    bool? isPrivate,
    String? gearId,
    int? achievementCount,
  }) {
    return Activity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      distance: distance ?? this.distance,
      duration: duration ?? this.duration,
      averageSpeed: averageSpeed ?? this.averageSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      elevationGain: elevationGain ?? this.elevationGain,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      routePoints: routePoints ?? this.routePoints,
      type: type ?? this.type,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      photoUrl: photoUrl ?? this.photoUrl,
      kudos: kudos ?? this.kudos,
      comments: comments ?? this.comments,
      isPrivate: isPrivate ?? this.isPrivate,
      gearId: gearId ?? this.gearId,
      achievementCount: achievementCount ?? this.achievementCount,
    );
  }

  @override
  List<Object?> get props => [
    id, name, startTime, endTime, distance, duration,
    averageSpeed, maxSpeed, elevationGain, caloriesBurned, routePoints, type,
    averageHeartRate, maxHeartRate, kudos, isPrivate
  ];
}