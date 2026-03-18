import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/activity.dart';
import '../services/activity_service.dart';

part 'activity_provider.g.dart';

@riverpod
ActivityService activityService(ActivityServiceRef ref) {
  print('📦 Creating ActivityService');
  return ActivityService();
}

@riverpod
class CurrentActivity extends _$CurrentActivity {
  @override
  Activity? build() {
    return null;
  }

  void startNewActivity(String name, ActivityType type) {
    print('\n========== PROVIDER: START ACTIVITY ==========');
    print('📱 Name: $name');
    print('📱 Type: $type');

    try {
      final service = ref.read(activityServiceProvider);
      service.startNewActivity(name, type);

      final newState = service.currentActivity;
      state = newState;

      print('📱 Activity started with ID: ${newState?.id}');
      print('========== PROVIDER: START COMPLETE ==========\n');
    } catch (e) {
      print('❌ Provider error: $e');
    }
  }

  void updateActivity() {
    final service = ref.read(activityServiceProvider);
    state = service.currentActivity;
  }

  Future<void> finishActivity() async {
    print('\n========== PROVIDER: FINISH ACTIVITY ==========');
    print('📱 Current state before finish: ${state?.id}');

    try {
      final service = ref.read(activityServiceProvider);
      await service.finishActivity();

      print('📱 Setting state to null');
      state = null;

      print('📱 State set to null successfully');
      print('========== PROVIDER: FINISH COMPLETE ==========\n');

    } catch (e) {
      print('❌ Provider error in finishActivity: $e');
      state = null;
    }
  }

  void cancelActivity() {
    print('\n========== PROVIDER: CANCEL ACTIVITY ==========');
    final service = ref.read(activityServiceProvider);
    service.cancelActivity();
    state = null;
    print('========== PROVIDER: CANCEL COMPLETE ==========\n');
  }
}

@riverpod
Future<List<Activity>> activitiesList(ActivitiesListRef ref) async {
  print('\n========== PROVIDER: FETCHING HISTORY ==========');
  try {
    final service = ref.watch(activityServiceProvider);
    final activities = await service.getAllActivities();
    print('📋 Provider returning ${activities.length} activities');
    print('========== PROVIDER: FETCH COMPLETE ==========\n');
    return activities;
  } catch (e) {
    print('❌ Provider error fetching history: $e');
    return [];
  }
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