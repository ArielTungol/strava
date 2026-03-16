import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

class SafetyService {
  static final SafetyService _instance = SafetyService._internal();
  factory SafetyService() => _instance;
  SafetyService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  Timer? _beaconTimer;
  List<String> _emergencyContacts = [];
  bool _isBeaconActive = false;
  LatLng? _lastLocation;

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notifications.initialize(settings);
  }

  void addEmergencyContact(String phoneNumber) {
    if (!_emergencyContacts.contains(phoneNumber)) {
      _emergencyContacts.add(phoneNumber);
    }
  }

  void removeEmergencyContact(String phoneNumber) {
    _emergencyContacts.remove(phoneNumber);
  }

  List<String> getEmergencyContacts() => List.unmodifiable(_emergencyContacts);

  Future<void> sendSOS(LatLng currentLocation) async {
    _lastLocation = currentLocation;

    // Send SMS to all emergency contacts
    for (final contact in _emergencyContacts) {
      await _sendSMS(contact, currentLocation);
    }

    // Show notification
    await _showNotification(
      'SOS Sent',
      'Your location has been sent to your emergency contacts',
    );
  }

  Future<void> _sendSMS(String phoneNumber, LatLng location) async {
    final mapsUrl = 'https://maps.google.com/?q=${location.latitude},${location.longitude}';
    final message = 'SOS! I need help. My current location: $mapsUrl';

    final smsUri = Uri.parse('sms:$phoneNumber?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    }
  }

  void startBeaconTracking(LatLng startLocation) {
    _isBeaconActive = true;
    _lastLocation = startLocation;

    _beaconTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!_isBeaconActive) {
        timer.cancel();
        return;
      }

      // Send location to emergency contacts
      for (final contact in _emergencyContacts) {
        await _sendLocationUpdate(contact);
      }
    });
  }

  void stopBeaconTracking() {
    _isBeaconActive = false;
    _beaconTimer?.cancel();
  }

  Future<void> _sendLocationUpdate(String phoneNumber) async {
    if (_lastLocation == null) return;

    final mapsUrl = 'https://maps.google.com/?q=${_lastLocation!.latitude},${_lastLocation!.longitude}';
    final message = 'Beacon update - I\'m still active. Current location: $mapsUrl';

    final smsUri = Uri.parse('sms:$phoneNumber?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    }
  }

  void updateLocation(LatLng location) {
    _lastLocation = location;
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'safety_channel',
      'Safety Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notifications.show(
      0,
      title,
      body,
      details,
    );
  }

  bool get isBeaconActive => _isBeaconActive;
}