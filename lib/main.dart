import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'models/activity.dart';
import 'models/route_point.dart';
import 'models/user.dart';
import 'screens/home_screen.dart';
import 'providers/providers.dart';
import 'services/safety_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeHive();

  if (!kIsWeb) {
    await _requestPermissions();
    await SafetyService().initialize();
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

Future<void> _initializeHive() async {
  try {
    await Hive.initFlutter();

    print('📦 Registering Hive adapters...');

    // ✅ REGISTER ALL ADAPTERS - THIS IS CRITICAL!
    Hive.registerAdapter(ActivityAdapter());
    Hive.registerAdapter(ActivityTypeAdapter()); // THIS WAS MISSING!
    Hive.registerAdapter(RoutePointAdapter());
    Hive.registerAdapter(UserAdapter());

    await Hive.openBox<Activity>('activities');
    await Hive.openBox<User>('user');

    print('✅ Hive initialized successfully');
    print('📊 Activities box contains: ${Hive.box<Activity>('activities').length} activities');
  } catch (e) {
    print('❌ Hive initialization error: $e');
  }
}

Future<void> _requestPermissions() async {
  if (kIsWeb) return;

  try {
    await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.activityRecognition,
      Permission.notification,
    ].request();
    print('✅ Permissions requested');
  } catch (e) {
    print('❌ Permission error: $e');
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Strava Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.light,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}