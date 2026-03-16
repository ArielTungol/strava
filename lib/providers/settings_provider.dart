import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_provider.g.dart';

@riverpod
class TravelMode extends _$TravelMode {
  @override
  String build() {
    return 'running';
  }

  void setMode(String mode) {
    state = mode;
  }

  IconData getIcon() {
    switch (state) {
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

  Color getColor() {
    switch (state) {
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
}

@riverpod
class MapSettings extends _$MapSettings {
  @override
  MapSettingsData build() {
    return const MapSettingsData(
      zoom: 15.0,
      showTraffic: false,
      showSatellite: false,
    );
  }

  void setZoom(double zoom) {
    state = state.copyWith(zoom: zoom);
  }

  void toggleTraffic() {
    state = state.copyWith(showTraffic: !state.showTraffic);
  }

  void toggleSatellite() {
    state = state.copyWith(showSatellite: !state.showSatellite);
  }
}

class MapSettingsData {
  final double zoom;
  final bool showTraffic;
  final bool showSatellite;

  const MapSettingsData({
    required this.zoom,
    required this.showTraffic,
    required this.showSatellite,
  });

  MapSettingsData copyWith({
    double? zoom,
    bool? showTraffic,
    bool? showSatellite,
  }) {
    return MapSettingsData(
      zoom: zoom ?? this.zoom,
      showTraffic: showTraffic ?? this.showTraffic,
      showSatellite: showSatellite ?? this.showSatellite,
    );
  }
}