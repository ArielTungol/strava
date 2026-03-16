import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:latlong2/latlong.dart';
import '../services/osrm_service.dart';

part 'navigation_provider.g.dart';

@riverpod
OSRMService osrmService(OsrmServiceRef ref) {
  return OSRMService();
}

@riverpod
class NavigationState extends _$NavigationState {
  @override
  AsyncValue<NavigationData> build() {
    return const AsyncValue.data(NavigationData.empty());
  }

  Future<void> calculateRoute(LatLng start, LatLng end) async {
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      final route = await OSRMService.getRoute(start, end);
      final details = await OSRMService.getRouteDetails(start, end);

      return NavigationData(
        routePoints: route,
        distance: (details['distance'] as num).toDouble(),
        duration: (details['duration'] as num).toDouble(),
        instructions: _generateInstructions(route),
        places: _generatePlaces(route),
      );
    });
  }

  List<NavigationInstruction> _generateInstructions(List<LatLng> route) {
    if (route.length < 2) return [];

    final instructions = <NavigationInstruction>[];

    for (int i = 0; i < route.length - 1; i++) {
      if (i % 10 == 0) {
        instructions.add(
          const NavigationInstruction(
            instruction: 'Continue straight',
            distance: 500.0,
            icon: Icons.arrow_upward,
          ),
        );
      }
    }

    instructions.add(
      const NavigationInstruction(
        instruction: 'Arrive at destination',
        distance: 0,
        icon: Icons.flag,
      ),
    );

    return instructions;
  }

  List<String> _generatePlaces(List<LatLng> route) {
    return const [
      'Start',
      'Camias',
      'Baliti',
      'Pandacaqui',
      'Telapayong',
      'Arenas',
      'San Roque',
      'Bitas',
      'Culubasa',
      'Destination',
    ];
  }

  void clearRoute() {
    state = const AsyncValue.data(NavigationData.empty());
  }
}

@riverpod
class PinnedDestination extends _$PinnedDestination {
  @override
  LatLng? build() => null;

  void setDestination(LatLng destination) => state = destination;
  void clearDestination() => state = null;
}

@riverpod
class NavigationUIState extends _$NavigationUIState {
  @override
  bool build() => false;

  void startSelecting() => state = true;
  void stopSelecting() => state = false;
}

@riverpod
class TurnNotification extends _$TurnNotification {
  @override
  TurnNotificationData? build() => null;

  void showNotification(String instruction, String distance, IconData icon) {
    state = TurnNotificationData(
      instruction: instruction,
      distance: distance,
      icon: icon,
    );
  }

  void hideNotification() => state = null;
}

class NavigationData {
  final List<LatLng> routePoints;
  final double distance;
  final double duration;
  final List<NavigationInstruction> instructions;
  final List<String> places;

  const NavigationData({
    required this.routePoints,
    required this.distance,
    required this.duration,
    required this.instructions,
    required this.places,
  });

  const NavigationData.empty()
      : routePoints = const [],
        distance = 0,
        duration = 0,
        instructions = const [],
        places = const [];
}

class NavigationInstruction {
  final String instruction;
  final double distance;
  final IconData icon;

  const NavigationInstruction({
    required this.instruction,
    required this.distance,
    required this.icon,
  });
}

class TurnNotificationData {
  final String instruction;
  final String distance;
  final IconData icon;

  const TurnNotificationData({
    required this.instruction,
    required this.distance,
    required this.icon,
  });
}