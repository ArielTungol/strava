import 'dart:math'; // ADD THIS IMPORT for sin, cos, atan2, sqrt
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RoutePreviewWidget extends StatefulWidget {
  final List<LatLng> routePoints;
  final LatLng? startPoint;
  final LatLng? endPoint;
  final LatLng? currentLocation;
  final bool isLoading;
  final double initialZoom;

  const RoutePreviewWidget({
    super.key,
    required this.routePoints,
    this.startPoint,
    this.endPoint,
    this.currentLocation,
    this.isLoading = false,
    this.initialZoom = 13,
  });

  @override
  State<RoutePreviewWidget> createState() => _RoutePreviewWidgetState();
}

class _RoutePreviewWidgetState extends State<RoutePreviewWidget> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMapOnRoute();
    });
  }

  void _centerMapOnRoute() {
    if (widget.routePoints.isNotEmpty) {
      // Calculate bounds to show entire route
      double minLat = widget.routePoints.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      double maxLat = widget.routePoints.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      double minLng = widget.routePoints.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      double maxLng = widget.routePoints.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

      _mapController.move(
        LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
        widget.initialZoom,
      );
    } else if (widget.currentLocation != null) {
      _mapController.move(widget.currentLocation!, widget.initialZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading route...'),
          ],
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.currentLocation ??
                (widget.routePoints.isNotEmpty ? widget.routePoints.first : const LatLng(14.5995, 120.9842)),
            initialZoom: widget.initialZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.trackmaster',
            ),

            // Route polyline
            if (widget.routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.routePoints,
                    color: Colors.blue.withValues(alpha: 0.7), // FIXED: replaced withOpacity with withValues
                    strokeWidth: 4,
                  ),
                ],
              ),

            // Markers
            MarkerLayer(
              markers: [
                // Start point marker
                if (widget.startPoint != null)
                  Marker(
                    point: widget.startPoint!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3), // FIXED
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.flag,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                // End point marker
                if (widget.endPoint != null)
                  Marker(
                    point: widget.endPoint!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3), // FIXED
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                // Current location marker
                if (widget.currentLocation != null)
                  Marker(
                    point: widget.currentLocation!,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.5), // FIXED
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.navigation,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        // Map controls
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1), // FIXED
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom + 1,
                        );
                      },
                    ),
                    Container(height: 1, width: 30, color: Colors.grey.shade300),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom - 1,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (widget.currentLocation != null)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1), // FIXED
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.my_location),
                    onPressed: () {
                      _mapController.move(widget.currentLocation!, 16);
                    },
                  ),
                ),
            ],
          ),
        ),

        // Route info overlay
        if (widget.routePoints.isNotEmpty)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15), // FIXED
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoItem(
                    'Distance',
                    _calculateDistance(),
                    Icons.straighten,
                  ),
                  _buildInfoItem(
                    'Points',
                    '${widget.routePoints.length}',
                    Icons.route,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  String _calculateDistance() {
    if (widget.routePoints.length < 2) return '0m';

    double totalDistance = 0;
    for (int i = 0; i < widget.routePoints.length - 1; i++) {
      totalDistance += _calculateDistanceBetween(
        widget.routePoints[i],
        widget.routePoints[i + 1],
      );
    }

    if (totalDistance < 1000) {
      return '${totalDistance.toStringAsFixed(0)}m';
    }
    return '${(totalDistance / 1000).toStringAsFixed(1)}km';
  }

  double _calculateDistanceBetween(LatLng p1, LatLng p2) {
    const double R = 6371000; // Earth's radius in meters
    double lat1 = p1.latitude * pi / 180;
    double lat2 = p2.latitude * pi / 180;
    double deltaLat = (p2.latitude - p1.latitude) * pi / 180;
    double deltaLng = (p2.longitude - p1.longitude) * pi / 180;

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) *
            sin(deltaLng / 2) * sin(deltaLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }
}