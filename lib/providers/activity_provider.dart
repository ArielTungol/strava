import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/activity.dart';
import '../services/activity_service.dart';

part 'activity_provider.g.dart';

@riverpod
ActivityService activityService(ActivityServiceRef ref) {
  return ActivityService();
}

@riverpod
class CurrentActivity extends _$CurrentActivity {
  @override
  Activity? build() {
    return null;
  }

  void startNewActivity(String name, ActivityType type) {
    print('📱 Starting new activity: $name');
    final service = ref.read(activityServiceProvider);
    service.startNewActivity(name, type);
    state = service.currentActivity;
  }

  void updateActivity() {
    final service = ref.read(activityServiceProvider);
    state = service.currentActivity;
  }

  Future<void> finishActivity() async {
    print('📱 Finish activity called');

    try {
      final service = ref.read(activityServiceProvider);
      await service.finishActivity();
      print('📱 Service finished activity');
      state = null;
      print('📱 State set to null');
    } catch (e) {
      print('📱 Error: $e');
      state = null;
    }
  }

  void cancelActivity() {
    final service = ref.read(activityServiceProvider);
    service.cancelActivity();
    state = null;
  }
}

@riverpod
Future<List<Activity>> activitiesList(ActivitiesListRef ref) async {
  print('📋 Fetching activities list');
  final service = ref.watch(activityServiceProvider);
  final activities = await service.getAllActivities();
  print('📋 Found ${activities.length} activities');
  return activities;
}

@riverpod
class SelectedActivity extends _$SelectedActivity {
  @override
  Activity? build() {
    return null;
  }

  void selectActivity(Activity activity) {
    state = activity;
  }

  void clearSelection() {
    state = null;
  }
}

@riverpod
class ActivityStats extends _$ActivityStats {
  @override
  Future<Map<String, dynamic>> build() async {
    final activities = await ref.watch(activitiesListProvider.future);
    return _calculateStats(activities);
  }

  Map<String, dynamic> _calculateStats(List<Activity> activities) {
    if (activities.isEmpty) {
      return {
        'totalActivities': 0,
        'totalDistance': 0.0,
        'totalDuration': 0.0,
        'totalElevation': 0.0,
        'averageDistance': 0.0,
        'averageDuration': 0.0,
      };
    }

    final totalDistance = activities.fold<double>(0, (sum, a) => sum + a.distance);
    final totalDuration = activities.fold<double>(0, (sum, a) => sum + a.duration);
    final totalElevation = activities.fold<double>(0, (sum, a) => sum + (a.elevationGain ?? 0));

    return {
      'totalActivities': activities.length,
      'totalDistance': totalDistance,
      'totalDuration': totalDuration,
      'totalElevation': totalElevation,
      'averageDistance': totalDistance / activities.length,
      'averageDuration': totalDuration / activities.length,
    };
  }
}