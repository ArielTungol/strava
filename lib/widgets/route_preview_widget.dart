import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RoutePreviewWidget extends StatelessWidget {
  final List<LatLng> routePoints;
  final LatLng? startPoint;
  final LatLng? endPoint;
  final LatLng? currentLocation;
  final bool isLoading;

  const RoutePreviewWidget({
    super.key,
    required this.routePoints,
    this.startPoint,
    this.endPoint,
    this.currentLocation,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: currentLocation ?? const LatLng(14.5995, 120.9842),
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.strava',
        ),
        if (routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: Colors.blue.withValues(alpha: 0.7),
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (startPoint != null)
              Marker(
                point: startPoint!,
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.flag, color: Colors.white, size: 20),
                ),
              ),
            if (endPoint != null)
              Marker(
                point: endPoint!,
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                ),
              ),
            if (currentLocation != null)
              Marker(
                point: currentLocation!,
                width: 30,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.navigation, color: Colors.white, size: 16),
                ),
              ),
          ],
        ),
      ],
    );
  }
}