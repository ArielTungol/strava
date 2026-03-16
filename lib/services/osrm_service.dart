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
                '?overview=full&geometries=geojson&steps=true'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry'];
          final List<LatLng> points = [];

          if (geometry['type'] == 'LineString') {
            final coords = geometry['coordinates'] as List;
            for (var coord in coords) {
              points.add(LatLng(coord[1], coord[0]));
            }
          }
          return points;
        }
      }
    } catch (e) {
      print('OSRM routing error: $e');
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
                '?overview=false&steps=true'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          return {
            'distance': route['distance'],
            'duration': route['duration'],
          };
        }
      }
    } catch (e) {
      print('OSRM details error: $e');
    }
    return {'distance': 0, 'duration': 0};
  }
}