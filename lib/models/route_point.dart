import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

part 'route_point.g.dart';

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