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

  // Initialize Hive database
  await _initializeHive();

  // Only request permissions and initialize native services on mobile
  if (!kIsWeb) {
    await _requestPermissions();
    await SafetyService().initialize();
  } else {
    debugPrint('📱 Running on web - permissions and native services are not supported');
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

/// Initialize Hive local database
Future<void> _initializeHive() async {
  try {
    await Hive.initFlutter();

    // Register Hive adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ActivityAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ActivityTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(RoutePointAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(UserAdapter());
    }

    // Open boxes
    await Hive.openBox<Activity>('activities');
    await Hive.openBox<User>('user');

    debugPrint('✅ Hive initialized successfully');
  } catch (e) {
    debugPrint('❌ Hive initialization error: $e');
  }
}

/// Request necessary permissions (mobile only)
Future<void> _requestPermissions() async {
  // Skip permission requests on web
  if (kIsWeb) return;

  try {
    // Request location permissions
    final statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.activityRecognition,
      Permission.notification,
    ].request();

    // Check if permissions were granted
    if (statuses[Permission.location]?.isGranted ?? false) {
      debugPrint('✅ Location permission granted');
    } else {
      debugPrint('⚠️ Location permission denied');
    }

    if (statuses[Permission.notification]?.isGranted ?? false) {
      debugPrint('✅ Notification permission granted');
    }
  } catch (e) {
    debugPrint('❌ Permission request error: $e');
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Strava Clone',
      debugShowCheckedModeBanner: false,

      // Light theme
      theme: ThemeData(
        primarySwatch: Colors.orange,
        useMaterial3: true,
        fontFamily: kIsWeb ? 'Roboto' : '.SF Pro Display', // Platform-specific font
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Colors.orange,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
      ),

      // Dark theme
      darkTheme: ThemeData(
        primarySwatch: Colors.orange,
        useMaterial3: true,
        fontFamily: kIsWeb ? 'Roboto' : '.SF Pro Display',
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Colors.orange,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
      ),

      themeMode: ThemeMode.system, // Follow system theme
      home: const HomeScreen(),
    );
  }
}