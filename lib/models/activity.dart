import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

part 'activity.g.dart';

@HiveType(typeId: 0)
enum ActivityType {
  @HiveField(0)
  running,
  @HiveField(1)
  walking,
  @HiveField(2)
  cycling,
}

@HiveType(typeId: 1)
class RoutePoint {
  @HiveField(0)
  final double latitude;
  @HiveField(1)
  final double longitude;
  @HiveField(2)
  final DateTime timestamp;
  @HiveField(3)
  final double speed;
  @HiveField(4)
  final double altitude;

  RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.speed,
    required this.altitude,
  });

  LatLng toLatLng() => LatLng(latitude, longitude);
}

@HiveType(typeId: 2)
class Activity {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final ActivityType type;
  @HiveField(3)
  final DateTime startTime;
  @HiveField(4)
  DateTime? endTime;
  @HiveField(5)
  final List<RoutePoint> routePoints;
  @HiveField(6)
  double distance;
  @HiveField(7)
  double duration;
  @HiveField(8)
  double averageSpeed;
  @HiveField(9)
  double maxSpeed;
  @HiveField(10)
  double elevationGain;
  @HiveField(11)
  LatLng? destination;

  Activity({
    required this.id,
    required this.name,
    required this.type,
    required this.startTime,
    this.endTime,
    required this.routePoints,
    this.distance = 0,
    this.duration = 0,
    this.averageSpeed = 0,
    this.maxSpeed = 0,
    this.elevationGain = 0,
    this.destination,
  });

  String get formattedDistance {
    if (distance < 1000) return '${distance.toStringAsFixed(0)}m';
    return '${(distance / 1000).toStringAsFixed(2)}km';
  }

  String get formattedDuration {
    if (duration < 60) return '${duration.toStringAsFixed(0)}s';
    if (duration < 3600) {
      int minutes = (duration / 60).floor();
      int seconds = (duration % 60).floor();
      return '${minutes}m ${seconds}s';
    }
    int hours = (duration / 3600).floor();
    int minutes = ((duration % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }

  String get formattedPace {
    if (type == ActivityType.cycling) {
      double speedKmh = averageSpeed * 3.6;
      return '${speedKmh.toStringAsFixed(1)} km/h';
    } else {
      if (averageSpeed <= 0) return '--:--';
      double pace = 1000 / (averageSpeed * 60);
      int minutes = pace.floor();
      int seconds = ((pace - minutes) * 60).floor();
      return '${minutes}:${seconds.toString().padLeft(2, '0')} /km';
    }
  }

  String get formattedSpeed {
    if (type == ActivityType.cycling) {
      double speedKmh = averageSpeed * 3.6;
      return '${speedKmh.toStringAsFixed(1)} km/h';
    } else {
      return '${averageSpeed.toStringAsFixed(1)} m/s';
    }
  }
}