import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/activity.dart';
import '../services/activity_service.dart';

part 'activity_provider.g.dart';

@riverpod
ActivityService activityService(ActivityServiceRef ref) {
  print('📦 Provider: Creating ActivityService instance');
  return ActivityService();
}

@riverpod
class CurrentActivity extends _$CurrentActivity {
  @override
  Activity? build() {
    print('📱 CurrentActivity: Building provider, current state: ${super.state?.name ?? "null"}');
    return null;
  }

  void startNewActivity(String name, ActivityType type) {
    print('\n========== START NEW ACTIVITY ==========');
    print('📱 CurrentActivity: startNewActivity() called');
    print('  - Name: $name');
    print('  - Type: $type');

    try {
      final service = ref.read(activityServiceProvider);
      print('📱 CurrentActivity: Got service instance');

      service.startNewActivity(name, type);
      print('📱 CurrentActivity: Service started activity');

      state = service.currentActivity;
      print('📱 CurrentActivity: State updated to: ${state?.id}');
      print('📱 CurrentActivity: Activity name: ${state?.name}');
      print('========== END START NEW ACTIVITY ==========\n');
    } catch (e) {
      print('❌ CurrentActivity: Error starting activity: $e');
      print('========== END WITH ERROR ==========\n');
    }
  }

  void updateActivity() {
    print('📱 CurrentActivity: updateActivity() called');
    try {
      final service = ref.read(activityServiceProvider);
      final newState = service.currentActivity;
      print('📱 CurrentActivity: Previous state: ${state?.distance} meters');
      print('📱 CurrentActivity: New state: ${newState?.distance} meters');
      state = newState;
    } catch (e) {
      print('❌ CurrentActivity: Error updating activity: $e');
    }
  }

  Future<void> finishActivity() async {
    print('\n========== FINISH ACTIVITY ==========');
    print('📱 CurrentActivity: finishActivity() called');
    print('📱 CurrentActivity: Current state before finish: ${state?.id}');
    print('📱 CurrentActivity: Distance: ${state?.distance} meters');
    print('📱 CurrentActivity: Duration: ${state?.duration} seconds');

    try {
      final service = ref.read(activityServiceProvider);
      print('📱 CurrentActivity: Got service, calling service.finishActivity()');

      await service.finishActivity();
      print('📱 CurrentActivity: service.finishActivity() completed successfully');

      print('📱 CurrentActivity: Setting state to null');
      state = null;

      print('📱 CurrentActivity: State set to null successfully');

      // Verify by reading from service again
      final afterFinish = service.currentActivity;
      print('📱 CurrentActivity: Service currentActivity after finish: ${afterFinish?.id ?? "null"}');

      print('========== FINISH ACTIVITY COMPLETE ==========\n');

    } catch (e) {
      print('❌ CurrentActivity: ERROR in finishActivity: $e');
      print('❌ CurrentActivity: Error type: ${e.runtimeType}');
      print('❌ CurrentActivity: Stack trace:');
      print(StackTrace.current);

      // Still set state to null even on error
      state = null;
      print('📱 CurrentActivity: State set to null after error');
      print('========== FINISH ACTIVITY ERROR ==========\n');
    }
  }

  void cancelActivity() {
    print('\n========== CANCEL ACTIVITY ==========');
    print('📱 CurrentActivity: cancelActivity() called');
    print('📱 CurrentActivity: Current state before cancel: ${state?.id}');

    try {
      final service = ref.read(activityServiceProvider);
      service.cancelActivity();
      print('📱 CurrentActivity: Service cancelled activity');

      state = null;
      print('📱 CurrentActivity: State set to null');

    } catch (e) {
      print('❌ CurrentActivity: Error cancelling activity: $e');
      state = null;
    }
    print('========== END CANCEL ACTIVITY ==========\n');
  }
}

@riverpod
Future<List<Activity>> activitiesList(ActivitiesListRef ref) async {
  print('\n========== FETCHING ACTIVITIES LIST ==========');
  print('📋 activitiesList: Provider building');

  try {
    final service = ref.watch(activityServiceProvider);
    print('📋 activitiesList: Got service instance');

    final activities = await service.getAllActivities();
    print('📋 activitiesList: Found ${activities.length} activities');

    if (activities.isEmpty) {
      print('📋 activitiesList: No activities found in database');
    } else {
      print('📋 activitiesList: Listing all activities:');
      for (var i = 0; i < activities.length; i++) {
        final activity = activities[i];
        print('  📋 [${i + 1}] ${activity.name}');
        print('      - ID: ${activity.id}');
        print('      - Type: ${activity.type}');
        print('      - Date: ${activity.formattedDate}');
        print('      - Distance: ${activity.formattedDistance}');
        print('      - Duration: ${activity.formattedDuration}');
        print('      - Calories: ${activity.caloriesBurned}');
      }
    }

    print('========== END FETCHING ACTIVITIES LIST ==========\n');
    return activities;

  } catch (e) {
    print('❌ activitiesList: Error fetching activities: $e');
    print('❌ activitiesList: Error type: ${e.runtimeType}');
    print('========== END WITH ERROR ==========\n');
    return []; // Return empty list on error
  }
}

@riverpod
class SelectedActivity extends _$SelectedActivity {
  @override
  Activity? build() {
    return null;
  }

  void selectActivity(Activity activity) {
    print('📌 SelectedActivity: Selecting activity: ${activity.name}');
    state = activity;
  }

  void clearSelection() {
    print('📌 SelectedActivity: Clearing selection');
    state = null;
  }
}

@riverpod
class ActivityStats extends _$ActivityStats {
  @override
  Future<Map<String, dynamic>> build() async {
    print('\n========== CALCULATING STATS ==========');
    print('📊 ActivityStats: Building stats');

    try {
      final activities = await ref.watch(activitiesListProvider.future);
      print('📊 ActivityStats: Got ${activities.length} activities for stats calculation');

      final stats = _calculateStats(activities);

      print('📊 ActivityStats: Stats calculated:');
      print('  - Total Activities: ${stats['totalActivities']}');
      print('  - Total Distance: ${stats['totalDistance']} meters');
      print('  - Total Duration: ${stats['totalDuration']} seconds');
      print('  - Total Elevation: ${stats['totalElevation']} meters');

      print('========== END STATS CALCULATION ==========\n');
      return stats;

    } catch (e) {
      print('❌ ActivityStats: Error calculating stats: $e');
      print('========== END WITH ERROR ==========\n');
      return {
        'totalActivities': 0,
        'totalDistance': 0.0,
        'totalDuration': 0.0,
        'totalElevation': 0.0,
        'averageDistance': 0.0,
        'averageDuration': 0.0,
      };
    }
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