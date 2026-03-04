import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OSRMService {
  static const String baseUrl = 'https://router.project-osrm.org';

  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/route/v1/driving/'
                '${start.longitude},${start.latitude};'
                '${end.longitude},${end.latitude}'
                '?overview=full&geometries=geojson&steps=true'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry'];

          List<LatLng> points = [];
          if (geometry['type'] == 'LineString') {
            final coords = geometry['coordinates'];
            for (var coord in coords) {
              points.add(LatLng(coord[1], coord[0]));
            }
          }

          print('✅ OSRM route found with ${points.length} points');
          return points;
        }
      }
    } catch (e) {
      print('❌ OSRM routing error: $e');
    }

    return [];
  }

  static Future<Map<String, dynamic>> getRouteDetails(LatLng start, LatLng end) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/route/v1/driving/'
                '${start.longitude},${start.latitude};'
                '${end.longitude},${end.latitude}'
                '?overview=full&geometries=geojson&steps=true&annotations=true'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];

          List<LatLng> points = [];
          if (geometry['type'] == 'LineString') {
            final coords = geometry['coordinates'];
            for (var coord in coords) {
              points.add(LatLng(coord[1], coord[0]));
            }
          }

          return {
            'route': points,
            'distance': route['distance'], // in meters
            'duration': route['duration'], // in seconds
          };
        }
      }
    } catch (e) {
      print('❌ OSRM details error: $e');
    }

    return {
      'route': [],
      'distance': 0,
      'duration': 0,
    };
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  static String formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    if (seconds < 3600) {
      int minutes = (seconds / 60).floor();
      int remainingSeconds = (seconds % 60).floor();
      return '${minutes}m ${remainingSeconds}s';
    }
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }
}