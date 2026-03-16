import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';

part 'route_point.g.dart';

@HiveType(typeId: 2)
class RoutePoint extends Equatable {
  @HiveField(0)
  final double latitude;

  @HiveField(1)
  final double longitude;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final double? altitude;

  @HiveField(4)
  final double? speed;

  @HiveField(5)
  final double? accuracy;

  @HiveField(6)
  final double? heartRate;

  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.altitude,
    this.speed,
    this.accuracy,
    this.heartRate,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      latitude: json['latitude'],
      longitude: json['longitude'],
      timestamp: DateTime.parse(json['timestamp']),
      altitude: json['altitude'],
      speed: json['speed'],
      accuracy: json['accuracy'],
      heartRate: json['heartRate'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'altitude': altitude,
      'speed': speed,
      'accuracy': accuracy,
      'heartRate': heartRate,
    };
  }

  RoutePoint copyWith({
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    double? altitude,
    double? speed,
    double? accuracy,
    double? heartRate,
  }) {
    return RoutePoint(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
      heartRate: heartRate ?? this.heartRate,
    );
  }

  @override
  List<Object?> get props => [latitude, longitude, timestamp, altitude, speed, accuracy, heartRate];
}