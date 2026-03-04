import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'models/activity.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request location permission only on mobile/desktop
  if (!kIsWeb) {
    await _requestPermissions();
  } else {
    print("Running on web - permissions handled by browser");
  }

  // Initialize Hive with a path for web
  await Hive.initFlutter();

  // Register adapters
  Hive.registerAdapter(ActivityAdapter());
  Hive.registerAdapter(ActivityTypeAdapter());
  Hive.registerAdapter(RoutePointAdapter());

  await Hive.openBox<Activity>('activities');

  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  // On web, this will be skipped
  if (kIsWeb) return;

  try {
    await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();
  } catch (e) {
    print("Permission error: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackMaster',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}