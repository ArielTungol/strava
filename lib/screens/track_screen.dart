import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';

import '../providers/activity_provider.dart';
import '../providers/location_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/settings_provider.dart';
import '../models/activity.dart';

class TrackScreen extends ConsumerStatefulWidget {
  const TrackScreen({super.key});

  @override
  ConsumerState<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends ConsumerState<TrackScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Animation for smooth marker movement
  AnimationController? _markerAnimationController;
  LatLng? _currentAnimatedPosition;

  Timer? _turnNotificationTimer;
  static const int _turnNotificationDurationMs = 4000;

  @override
  void initState() {
    super.initState();
    _initializeMarkerAnimation();
    _initializeLocation();
  }

  void _initializeMarkerAnimation() {
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  Future<void> _initializeLocation() async {
    // Request permission and get initial location
    await ref.read(locationPermissionStateProvider.notifier).checkAndRequestPermission();

    final locationNotifier = ref.read(currentLocationProvider.notifier);
    final service = ref.read(locationServiceProvider);

    final location = await service.getCurrentLocation();
    if (location != null) {
      locationNotifier.updateLocation(location);
      setState(() {
        _currentAnimatedPosition = location;
      });
      _mapController.move(location, 15);
    }
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * pi / 180;
    double lon1 = start.longitude * pi / 180;
    double lat2 = end.latitude * pi / 180;
    double lon2 = end.longitude * pi / 180;

    double y = sin(lon2 - lon1) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1);
    double bearing = atan2(y, x) * 180 / pi;

    return (bearing + 360) % 360;
  }

  void _animateMarkerToNewPosition(LatLng newPosition) {
    if (_currentAnimatedPosition == null) {
      setState(() {
        _currentAnimatedPosition = newPosition;
      });
      return;
    }

    final targetPosition = newPosition;
    _markerAnimationController?.stop();
    _markerAnimationController?.reset();

    final startLat = _currentAnimatedPosition!.latitude;
    final startLng = _currentAnimatedPosition!.longitude;
    final endLat = targetPosition.latitude;
    final endLng = targetPosition.longitude;

    _markerAnimationController?.addListener(() {
      if (!mounted) return;
      final double t = _markerAnimationController!.value;
      final double interpolatedLat = startLat + (endLat - startLat) * t;
      final double interpolatedLng = startLng + (endLng - startLng) * t;

      setState(() {
        _currentAnimatedPosition = LatLng(interpolatedLat, interpolatedLng);
      });
    });

    _markerAnimationController?.forward();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    final isSelecting = ref.read(navigationUIStateProvider);
    final currentActivity = ref.read(currentActivityProvider);

    if (isSelecting && currentActivity == null) {
      ref.read(pinnedDestinationProvider.notifier).setDestination(point);
      ref.read(navigationUIStateProvider.notifier).stopSelecting();

      final currentLocation = ref.read(currentLocationProvider);
      if (currentLocation != null) {
        ref.read(navigationStateProvider.notifier).calculateRoute(
          currentLocation,
          point,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pinned destination set!'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.purple,
        ),
      );
    }
  }

  void _centerOnCurrentLocation() {
    final currentLocation = ref.read(currentLocationProvider);
    if (currentLocation != null) {
      _mapController.move(currentLocation, 16);
    }
  }

  void _clearPinnedDestination() {
    ref.read(pinnedDestinationProvider.notifier).clearDestination();
    ref.read(navigationStateProvider.notifier).clearRoute();
    ref.read(turnNotificationProvider.notifier).hideNotification();
  }

  void _startTracking() {
    final travelMode = ref.read(travelModeProvider);
    final activityType = _getActivityTypeFromString(travelMode);

    ref.read(currentActivityProvider.notifier).startNewActivity(
      '${travelMode.capitalize()} ${DateTime.now().toString().substring(0, 16)}',
      activityType,
    );

    ref.read(locationTrackingProvider.notifier).startTracking();
  }

  ActivityType _getActivityTypeFromString(String mode) {
    switch (mode) {
      case 'walking':
        return ActivityType.walking;
      case 'cycling':
        return ActivityType.cycling;
      case 'hiking':
        return ActivityType.hiking;
      case 'swimming':
        return ActivityType.swimming;
      case 'workout':
        return ActivityType.workout;
      case 'running':
      default:
        return ActivityType.running;
    }
  }

  Future<void> _stopTracking() async {
    await ref.read(currentActivityProvider.notifier).finishActivity();
    ref.read(locationTrackingProvider.notifier).stopTracking();
    ref.read(currentSpeedProvider.notifier).resetSpeed();

    if (mounted) {
      _showActivitySummary();
    }
  }

  void _cancelTracking() {
    ref.read(currentActivityProvider.notifier).cancelActivity();
    ref.read(locationTrackingProvider.notifier).stopTracking();
    ref.read(currentSpeedProvider.notifier).resetSpeed();
    ref.read(pinnedDestinationProvider.notifier).clearDestination();
    ref.read(navigationStateProvider.notifier).clearRoute();
  }

  void _showActivitySummary() {
    final currentActivity = ref.read(currentActivityProvider);
    if (currentActivity == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Activity Completed! 🎉'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryRow('Distance', _formatDistance(currentActivity.distance)),
              const Divider(),
              _buildSummaryRow('Duration', _formatDuration(currentActivity.duration)),
              const Divider(),
              _buildSummaryRow('Avg Speed', _formatSpeed(currentActivity.averageSpeed, currentActivity.type)),
              const Divider(),
              _buildSummaryRow('Max Speed', _formatSpeed(currentActivity.maxSpeed ?? 0, currentActivity.type)),
              const Divider(),
              _buildSummaryRow('Calories', '${currentActivity.caloriesBurned} kcal'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _formatDuration(double seconds) {
    int hours = (seconds / 3600).floor();
    int minutes = ((seconds % 3600) / 60).floor();
    int secs = (seconds % 60).floor();

    if (hours > 0) return '${hours}h ${minutes}min';
    if (minutes > 0) return '${minutes}min';
    return '${secs}sec';
  }

  String _formatSpeed(double speed, ActivityType type) {
    if (type == ActivityType.cycling) {
      return '${(speed * 3.6).toStringAsFixed(1)} km/h';
    }
    return '${speed.toStringAsFixed(1)} m/s';
  }

  void _showPinnedRouteBottomSheet() {
    final navigationState = ref.read(navigationStateProvider).valueOrNull;
    if (navigationState == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.purple, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Pinned Route Details',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: const TabBar(
                        tabs: [
                          Tab(text: 'Directions'),
                          Tab(text: 'Places'),
                        ],
                        labelColor: Colors.purple,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Colors.purple,
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Directions Tab
                          ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: navigationState.instructions.length,
                            itemBuilder: (context, index) {
                              final instruction = navigationState.instructions[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        instruction.icon,
                                        color: Colors.purple,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            instruction.instruction,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDistance(instruction.distance),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          // Places Tab
                          ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: navigationState.places.length,
                            itemBuilder: (context, index) {
                              final place = navigationState.places[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: index < 3 ? Colors.purple : Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        place,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: index < 3 ? FontWeight.bold : FontWeight.normal,
                                          color: index < 3 ? Colors.black : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers
    final currentLocation = ref.watch(currentLocationProvider);
    final currentActivity = ref.watch(currentActivityProvider);
    final isTracking = currentActivity != null;
    final pinnedDestination = ref.watch(pinnedDestinationProvider);
    final navigationState = ref.watch(navigationStateProvider);
    final travelMode = ref.watch(travelModeProvider);
    final travelModeColor = _getTravelModeColor(travelMode);
    final turnNotification = ref.watch(turnNotificationProvider);
    final currentSpeed = ref.watch(currentSpeedProvider);

    // Get route points from navigation state
    final routePoints = navigationState.valueOrNull?.routePoints ?? [];
    final totalDistance = navigationState.valueOrNull?.distance ?? 0;
    final totalDuration = navigationState.valueOrNull?.duration ?? 0;

    // Update animated position when current location changes
    if (currentLocation != null && _currentAnimatedPosition != currentLocation) {
      _animateMarkerToNewPosition(currentLocation);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Activity'),
        backgroundColor: travelModeColor.withValues(alpha: 0.9),
        foregroundColor: Colors.white,
        actions: [
          if (!isTracking && pinnedDestination == null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.directions),
              onSelected: (value) => ref.read(travelModeProvider.notifier).setMode(value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'running',
                  child: Row(
                    children: [
                      Icon(Icons.directions_run, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Running')
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'walking',
                  child: Row(
                    children: [
                      Icon(Icons.directions_walk, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Walking')
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cycling',
                  child: Row(
                    children: [
                      Icon(Icons.directions_bike, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Cycling')
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'hiking',
                  child: Row(
                    children: [
                      Icon(Icons.hiking, color: Colors.brown),
                      SizedBox(width: 8),
                      Text('Hiking')
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'swimming',
                  child: Row(
                    children: [
                      Icon(Icons.pool, color: Colors.lightBlue),
                      SizedBox(width: 8),
                      Text('Swimming')
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'workout',
                  child: Row(
                    children: [
                      Icon(Icons.fitness_center, color: Colors.purple),
                      SizedBox(width: 8),
                      Text('Workout')
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentLocation ?? const LatLng(14.5995, 120.9842),
              initialZoom: 15,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.strava',
                tileProvider: CancellableNetworkTileProvider(),
              ),

              // Route polyline
              if (routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      color: Colors.purple.withValues(alpha: 0.8),
                      strokeWidth: 5,
                    ),
                  ],
                ),

              // Destination circle
              if (pinnedDestination != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: pinnedDestination,
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderColor: Colors.purple,
                      borderStrokeWidth: 2,
                      radius: 15,
                    ),
                  ],
                ),

              // Markers
              MarkerLayer(
                markers: [
                  // Current position marker
                  if (_currentAnimatedPosition != null)
                    Marker(
                      point: _currentAnimatedPosition!,
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeInOut,
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: travelModeColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: travelModeColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Pinned destination marker
                  if (pinnedDestination != null)
                    Marker(
                      point: pinnedDestination,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_pin, color: Colors.purple, size: 40),
                    ),
                ],
              ),
            ],
          ),

          // Navigation header for pinned destination
          if (pinnedDestination != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10),
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
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.location_on, color: Colors.purple, size: 20),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Pinned Destination',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.purple),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatTime(DateTime.now().add(Duration(seconds: totalDuration.round()))),
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatDistance(totalDistance)} • ${_formatDuration(totalDuration)}',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: travelModeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(_getTravelModeIcon(travelMode), size: 16, color: travelModeColor),
                              const SizedBox(width: 4),
                              Text(
                                travelMode.capitalize(),
                                style: TextStyle(color: travelModeColor, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Live tracking stats
          if (isTracking)
            Positioned(
              top: pinnedDestination != null ? 200 : 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCompactStat(
                      value: _formatDistance(currentActivity?.distance ?? 0),
                      icon: Icons.straighten,
                      color: travelModeColor,
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    _buildCompactStat(
                      value: _formatDuration(currentActivity?.duration ?? 0),
                      icon: Icons.timer,
                      color: travelModeColor,
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    _buildCompactStat(
                      value: _formatSpeed(currentSpeed, currentActivity?.type ?? ActivityType.running),
                      icon: Icons.speed,
                      color: travelModeColor,
                    ),
                  ],
                ),
              ),
            ),

          // Turn notification
          if (turnNotification != null)
            Positioned(
              top: pinnedDestination != null ? 270 : (isTracking ? 100 : 80),
              left: 20,
              right: 20,
              child: TweenAnimationBuilder(
                duration: const Duration(milliseconds: 300),
                tween: Tween<double>(begin: 0, end: 1),
                curve: Curves.easeOutBack,
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (pinnedDestination != null ? Colors.purple : travelModeColor).withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                        border: Border.all(
                          color: pinnedDestination != null ? Colors.purple : travelModeColor,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (pinnedDestination != null ? Colors.purple : travelModeColor).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(turnNotification.icon, color: pinnedDestination != null ? Colors.purple : travelModeColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  turnNotification.instruction,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'in ${turnNotification.distance}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Route button
          if (pinnedDestination != null)
            Positioned(
              top: isTracking ? 260 : 220,
              left: 16,
              child: _buildActionButton(
                icon: Icons.route,
                label: 'Pinned Route',
                color: Colors.purple,
                onPressed: _showPinnedRouteBottomSheet,
              ),
            ),

          // Clear pin button
          if (pinnedDestination != null)
            Positioned(
              top: 220,
              right: 16,
              child: _buildActionButton(
                icon: Icons.clear,
                label: 'Clear Pin',
                color: Colors.red,
                onPressed: _clearPinnedDestination,
              ),
            ),

          // Map controls
          Positioned(
            bottom: 100,
            right: 16,
            child: Column(
              children: [
                _buildControlButton(Icons.add, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1)),
                const SizedBox(height: 8),
                _buildControlButton(Icons.remove, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1)),
                const SizedBox(height: 8),
                _buildControlButton(Icons.my_location, _centerOnCurrentLocation),

                if (!isTracking && pinnedDestination == null) ...[
                  const SizedBox(height: 8),
                  _buildControlButton(
                    Icons.push_pin,
                        () {
                      ref.read(navigationUIStateProvider.notifier).startSelecting();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tap on the map to set a pinned destination'),
                          duration: Duration(seconds: 3),
                          backgroundColor: Colors.purple,
                        ),
                      );
                    },
                    color: Colors.purple,
                  ),
                ],
              ],
            ),
          ),

          // Start/Stop buttons
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isTracking)
                      ElevatedButton(
                        onPressed: currentLocation != null ? _startTracking : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: travelModeColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(100, 36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Start'),
                      ),
                    if (isTracking) ...[
                      ElevatedButton(
                        onPressed: _stopTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(80, 36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Finish'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _cancelTracking,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          minimumSize: const Size(80, 36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTravelModeColor(String mode) {
    switch (mode) {
      case 'running':
        return Colors.orange;
      case 'walking':
        return Colors.green;
      case 'cycling':
        return Colors.blue;
      case 'hiking':
        return Colors.brown;
      case 'swimming':
        return Colors.lightBlue;
      case 'workout':
        return Colors.purple;
      default:
        return Colors.orange;
    }
  }

  IconData _getTravelModeIcon(String mode) {
    switch (mode) {
      case 'running':
        return Icons.directions_run;
      case 'walking':
        return Icons.directions_walk;
      case 'cycling':
        return Icons.directions_bike;
      case 'hiking':
        return Icons.hiking;
      case 'swimming':
        return Icons.pool;
      case 'workout':
        return Icons.fitness_center;
      default:
        return Icons.directions_run;
    }
  }

  Widget _buildCompactStat({required String value, required IconData icon, required Color color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {Color color = Colors.blue}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }

  String _formatTime(DateTime time) {
    int hour = time.hour;
    int minute = time.minute;
    String period = hour >= 12 ? 'PM' : 'AM';

    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;

    return '$hour:${minute.toString().padLeft(2, '0')} $period';
  }

  @override
  void dispose() {
    _markerAnimationController?.dispose();
    _turnNotificationTimer?.cancel();
    super.dispose();
  }
}

extension StringExtension on String {
  String capitalize() => "${this[0].toUpperCase()}${substring(1)}";
}